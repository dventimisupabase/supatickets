-- ==============================================================================
-- 1. EXTENSIONS
-- ==============================================================================
-- Enable the necessary Supabase extensions for queues, cron jobs, and webhooks
CREATE EXTENSION IF NOT EXISTS pgmq;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Initialize the queue where our intents will be temporarily stored
SELECT pgmq.create('intake_queue');

-- ==============================================================================
-- 2. TYPES & TABLES
-- ==============================================================================
-- Define the states of a resource (e.g., a ticket)
CREATE TYPE slot_status AS ENUM ('AVAILABLE', 'RESERVED', 'CONSUMED');

-- The Core Inventory Table
-- CRITICAL: This is an UNLOGGED table. It skips the Postgres Write-Ahead Log (WAL)
-- to allow for extreme write velocity during a traffic spike. It is ephemeral.
CREATE UNLOGGED TABLE inventory_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pool_id TEXT NOT NULL, -- e.g., 'taylor_swift_la_night_1'
    status slot_status NOT NULL DEFAULT 'AVAILABLE',
    locked_by TEXT,        -- The user_id who grabbed it
    locked_at TIMESTAMPTZ,
    
    -- Index to make the SKIP LOCKED query as fast as possible
    CONSTRAINT unique_slot UNIQUE (id)
);

CREATE INDEX idx_available_slots ON inventory_slots (pool_id, status) 
WHERE status = 'AVAILABLE';

-- The Engine Configuration Table (For Live Throttling)
CREATE TABLE engine_config (
    pool_id TEXT PRIMARY KEY,
    batch_size INT NOT NULL DEFAULT 100,
    is_active BOOLEAN NOT NULL DEFAULT true
);

-- The Metrics Table (For the God-Mode Dashboard)
CREATE TABLE engine_metrics (
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    pool_id TEXT NOT NULL,
    available_slots INT,
    queue_depth INT
);

-- ==============================================================================
-- 3. THE MAGIC: HIGH-CONCURRENCY CLAIM FUNCTION
-- ==============================================================================
-- This is the function the frontend or Edge Function calls when a user clicks "Buy".
-- It uses SKIP LOCKED to completely bypass row contention.
CREATE OR REPLACE FUNCTION claim_resource_and_queue(
    p_pool_id TEXT, 
    p_user_id TEXT
) RETURNS UUID AS $$
DECLARE
    claimed_slot_id UUID;
    queue_msg_id BIGINT;
    payload JSONB;
BEGIN
    -- 1. Grab the exact next available slot, ignoring anyone else's locks instantly
    UPDATE inventory_slots
    SET 
        status = 'RESERVED',
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

    -- 2. If we got one, push the intent to the pgmq queue immediately
    IF claimed_slot_id IS NOT NULL THEN
        
        -- Construct the payload with the 'queued' state
        payload := jsonb_build_object(
            'pool_id', p_pool_id,
            'resource_id', claimed_slot_id,
            'user_id', p_user_id,
            'state', 'queued'
        );

        -- Send to pgmq (returns the message ID which we can use as an idempotency key)
        SELECT pgmq.send('intake_queue', payload) INTO queue_msg_id;
        
    END IF;

    -- 3. Return the ticket ID to the user (or NULL if sold out)
    RETURN claimed_slot_id;
END;
$$ LANGUAGE plpgsql;

-- ==============================================================================
-- 4. BACKGROUND WORKERS & METRICS
-- ==============================================================================

-- A background function to snapshot metrics without locking the main tables
CREATE OR REPLACE FUNCTION snapshot_engine_metrics() RETURNS VOID AS $$
BEGIN
    INSERT INTO engine_metrics (pool_id, available_slots, queue_depth)
    SELECT 
        'taylor_swift_la_night_1',
        (SELECT COUNT(*) FROM inventory_slots WHERE status = 'AVAILABLE'),
        (SELECT queue_length FROM pgmq.metrics('intake_queue'));
END;
$$ LANGUAGE plpgsql;

-- Schedule the metrics snapshot to run every minute (pg_cron minimum resolution)
-- (For higher frequency, this could be triggered by an external worker)
SELECT cron.schedule('metrics_snapshot', '* * * * *', 'SELECT snapshot_engine_metrics()');

-- Schedule the trigger that wakes up the Edge Function to drain the queue
-- (Replace with actual Edge Function URL and Service Role Key)
SELECT cron.schedule(
    'drain_queue_trigger',
    '* * * * *',
    $$
    SELECT net.http_post(
        url:='https://your-project-ref.supabase.co/functions/v1/bridge-worker',
        headers:='{"Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb
    )
    $$
);
