-- db1/supabase/migrations/20260303200001_decouple_claim_from_queue.sql
-- Decouple pgmq.send from claim_resource_and_queue for lower p95 latency.
-- Queue writes are now handled by a background sweep function.

-- (a) Add queued_at column to track which slots have been swept into the queue
ALTER TABLE inventory_slots ADD COLUMN queued_at TIMESTAMPTZ;

-- (b) Partial index for the sweep query (RESERVED but not yet queued)
CREATE INDEX idx_reserved_unqueued_slots
    ON inventory_slots (pool_id)
    WHERE status = 'RESERVED' AND queued_at IS NULL;

-- (c) Replace claim_resource_and_queue: remove pgmq.send, keep SECURITY DEFINER
CREATE OR REPLACE FUNCTION claim_resource_and_queue(
    p_pool_id TEXT,
    p_user_id TEXT
) RETURNS UUID AS $$
DECLARE
    claimed_slot_id UUID;
BEGIN
    UPDATE inventory_slots
    SET
        status    = 'RESERVED',
        locked_by = p_user_id,
        locked_at = NOW()
    WHERE id = (
        SELECT id
        FROM inventory_slots
        WHERE pool_id = p_pool_id
          AND status = 'AVAILABLE'
        LIMIT 1
        FOR UPDATE SKIP LOCKED
    )
    RETURNING id INTO claimed_slot_id;

    RETURN claimed_slot_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- (d) New sweep function: batch-enqueue RESERVED+unqueued slots
CREATE OR REPLACE FUNCTION sweep_reserved_to_queue(
    p_batch_limit INT DEFAULT 1000
) RETURNS INT AS $$
DECLARE
    swept_count INT := 0;
    r RECORD;
BEGIN
    FOR r IN
        SELECT id, pool_id, locked_by
        FROM inventory_slots
        WHERE status = 'RESERVED'
          AND queued_at IS NULL
        ORDER BY locked_at
        LIMIT p_batch_limit
        FOR UPDATE SKIP LOCKED
    LOOP
        PERFORM pgmq.send('intake_queue', jsonb_build_object(
            'pool_id',     r.pool_id,
            'resource_id', r.id,
            'user_id',     r.locked_by,
            'state',       'queued'
        ));

        UPDATE inventory_slots
        SET queued_at = now()
        WHERE id = r.id;

        swept_count := swept_count + 1;
    END LOOP;

    RETURN swept_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- (e) Update reap_orphaned_slots: only reap slots that were already swept
--     (queued_at IS NOT NULL) and whose queue message is gone.
--     Also clear queued_at when resetting a slot to AVAILABLE.
CREATE OR REPLACE FUNCTION reap_orphaned_slots(
    p_stale_threshold INTERVAL DEFAULT '10 minutes'
) RETURNS INT AS $$
DECLARE
    reaped_count INT;
BEGIN
    WITH stale_slots AS (
        SELECT s.id
        FROM inventory_slots s
        WHERE s.status = 'RESERVED'
          AND s.queued_at IS NOT NULL
          AND s.locked_at < now() - p_stale_threshold
          AND NOT EXISTS (
              SELECT 1
              FROM pgmq.q_intake_queue q
              WHERE q.message->>'resource_id' = s.id::text
          )
        FOR UPDATE SKIP LOCKED
    ),
    updated AS (
        UPDATE inventory_slots
        SET status    = 'AVAILABLE',
            locked_by = NULL,
            locked_at = NULL,
            queued_at = NULL
        WHERE id IN (SELECT id FROM stale_slots)
        RETURNING id
    )
    SELECT COUNT(*) INTO reaped_count FROM updated;

    RETURN reaped_count;
END;
$$ LANGUAGE plpgsql;

-- (f) Schedule sweep cron job: every minute
SELECT cron.schedule('sweep_reserved_to_queue', '* * * * *',
    'SELECT sweep_reserved_to_queue(1000)');

-- (g) Drop temporary benchmark function
DROP FUNCTION IF EXISTS claim_no_queue(TEXT, TEXT);
