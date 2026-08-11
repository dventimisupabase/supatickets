-- db1/supabase/migrations/20260305200001_unclaim_and_uuid_pool_ids.sql
-- (a) unclaim_slot: release all RESERVED slots for a user in a pool
-- (b) Fix claim_resource_and_queue: quote sequence name for UUID pool_ids,
--     add SKIP LOCKED fallback for recycled slots
-- (c) Re-declare reset_claim_sequence for completeness

-- (a) unclaim_slot
CREATE OR REPLACE FUNCTION unclaim_slot(
    p_pool_id TEXT,
    p_user_id TEXT
) RETURNS INT AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE inventory_slots
    SET status    = 'AVAILABLE',
        locked_by = NULL,
        locked_at = NULL,
        queued_at = NULL
    WHERE pool_id   = p_pool_id
      AND locked_by = p_user_id
      AND status    = 'RESERVED';

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- (b) Fix claim_resource_and_queue: format(%I) + SKIP LOCKED fallback
CREATE OR REPLACE FUNCTION claim_resource_and_queue(
    p_pool_id TEXT,
    p_user_id TEXT
) RETURNS UUID AS $$
DECLARE
    pos BIGINT;
    claimed_slot_id UUID;
BEGIN
    -- O(1): atomically grab next position (format %I handles hyphens in pool_id)
    pos := nextval(format('%I', 'claim_seq_' || p_pool_id));

    -- Direct index lookup on (pool_id, seq_pos); HOT-eligible update
    UPDATE inventory_slots
    SET status    = 'RESERVED',
        locked_by = p_user_id,
        locked_at = NOW()
    WHERE pool_id = p_pool_id
      AND seq_pos = pos
    RETURNING id INTO claimed_slot_id;

    -- Fallback: sequence advanced past all slots (burned positions from unclaims).
    -- Try any AVAILABLE slot via SKIP LOCKED.
    IF claimed_slot_id IS NULL THEN
        UPDATE inventory_slots
        SET status    = 'RESERVED',
            locked_by = p_user_id,
            locked_at = NOW()
        WHERE id = (
            SELECT id FROM inventory_slots
            WHERE pool_id = p_pool_id
              AND status  = 'AVAILABLE'
            LIMIT 1
            FOR UPDATE SKIP LOCKED
        )
        RETURNING id INTO claimed_slot_id;
    END IF;

    RETURN claimed_slot_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- (c) Re-declare reset_claim_sequence (already uses format(%I))
CREATE OR REPLACE FUNCTION reset_claim_sequence(
    p_pool_id TEXT,
    p_start BIGINT DEFAULT 1
) RETURNS VOID AS $$
BEGIN
    EXECUTE format(
        'CREATE SEQUENCE IF NOT EXISTS %I START %s',
        'claim_seq_' || p_pool_id, p_start
    );
    EXECUTE format(
        'ALTER SEQUENCE %I RESTART WITH %s',
        'claim_seq_' || p_pool_id, p_start
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
