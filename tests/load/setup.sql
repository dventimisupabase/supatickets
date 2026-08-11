-- tests/load/setup.sql
-- Run against DB1 before each load test run.
-- Creates a load_test pool with 500k available slots.

INSERT INTO engine_config (
    pool_id, batch_size, visibility_timeout_sec, max_retries, is_active
) VALUES (
    'load_test', 100, 45, 10, true
) ON CONFLICT (pool_id) DO NOTHING;

-- Truncate any leftover slots from a previous run, then refill.
DELETE FROM inventory_slots WHERE pool_id = 'load_test';

INSERT INTO inventory_slots (pool_id, status, seq_pos)
SELECT 'load_test', 'AVAILABLE', gs
FROM generate_series(1, 500000) AS gs;

-- Create/reset the claim sequence for sequence-based claiming
SELECT reset_claim_sequence('load_test', 1);
