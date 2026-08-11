-- db1/supabase/migrations/20260224100000_intake_engine_setup.sql

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgmq;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Queues
SELECT pgmq.create('intake_queue');
SELECT pgmq.create('intake_dlq');

-- Types
CREATE TYPE slot_status AS ENUM ('AVAILABLE', 'RESERVED', 'CONSUMED');

-- Inventory (UNLOGGED = no WAL, maximum write speed, ephemeral)
CREATE UNLOGGED TABLE inventory_slots (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pool_id   TEXT NOT NULL,
    status    slot_status NOT NULL DEFAULT 'AVAILABLE',
    locked_by TEXT,
    locked_at TIMESTAMPTZ
);
-- NO redundant UNIQUE constraint on PK (bug fix from original)

CREATE INDEX idx_available_slots
    ON inventory_slots (pool_id, status)
    WHERE status = 'AVAILABLE';

-- Engine config (all required columns from spec)
CREATE TABLE engine_config (
    pool_id                TEXT PRIMARY KEY,
    batch_size             INT NOT NULL DEFAULT 100,
    visibility_timeout_sec INT NOT NULL DEFAULT 45,
    max_retries            INT NOT NULL DEFAULT 10,
    is_active              BOOLEAN NOT NULL DEFAULT true,
    validation_webhook_url TEXT,
    commit_rpc_name        TEXT NOT NULL DEFAULT 'finalize_transaction',
    commit_webhook_url     TEXT
);

-- Metrics (fixed: added PK and index — bug fix from original)
CREATE TABLE engine_metrics (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    captured_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    pool_id         TEXT NOT NULL,
    available_slots INT NOT NULL,
    reserved_slots  INT NOT NULL,
    consumed_slots  INT NOT NULL,
    queue_depth     INT NOT NULL,
    dlq_depth       INT NOT NULL DEFAULT 0
);

CREATE INDEX idx_metrics_pool_ts
    ON engine_metrics (pool_id, captured_at DESC);
