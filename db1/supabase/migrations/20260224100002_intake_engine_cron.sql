-- db1/supabase/migrations/20260224100002_intake_engine_cron.sql

-- 1. reap_orphaned_slots: returns stale RESERVED slots to AVAILABLE
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
          AND s.locked_at < now() - p_stale_threshold
          -- No matching message in the queue (the queue table is pgmq.q_intake_queue)
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
            locked_at = NULL
        WHERE id IN (SELECT id FROM stale_slots)
        RETURNING id
    )
    SELECT COUNT(*) INTO reaped_count FROM updated;

    RETURN reaped_count;
END;
$$ LANGUAGE plpgsql;

-- 2. Cron: snapshot metrics every minute
SELECT cron.schedule(
    'metrics_snapshot',
    '* * * * *',
    'SELECT snapshot_engine_metrics()'
);

-- 3. Cron: reap orphaned slots every 2 minutes
SELECT cron.schedule(
    'reap_orphaned_slots',
    '*/2 * * * *',
    $$SELECT reap_orphaned_slots(interval '10 minutes')$$
);

-- 4. Cron: trigger bridge worker every minute via pg_net
-- URL and key are read from database settings to avoid hardcoding secrets
SELECT cron.schedule(
    'drain_queue_trigger',
    '* * * * *',
    $$
    SELECT net.http_post(
        url     := current_setting('app.bridge_worker_url'),
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
            'Content-Type',  'application/json'
        ),
        body    := '{}'::jsonb
    )
    $$
);
