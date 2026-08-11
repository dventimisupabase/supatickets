-- db1/supabase/tests/00004_sweep.test.sql
BEGIN;
SELECT plan(7);

-- Setup: seed config and inventory with 3 RESERVED+unqueued slots
INSERT INTO engine_config (pool_id, batch_size, visibility_timeout_sec, max_retries, is_active)
VALUES ('sweep_test_pool', 10, 45, 3, true)
ON CONFLICT (pool_id) DO NOTHING;

INSERT INTO inventory_slots (pool_id, status, locked_by, locked_at, queued_at)
VALUES
    ('sweep_test_pool', 'RESERVED', 'user_a', now() - interval '1 minute', NULL),
    ('sweep_test_pool', 'RESERVED', 'user_b', now() - interval '2 minutes', NULL),
    ('sweep_test_pool', 'RESERVED', 'user_c', now() - interval '3 minutes', NULL);

-- 1. Function exists
SELECT has_function('sweep_reserved_to_queue', 'sweep_reserved_to_queue function exists');

-- 2. Sweep returns correct count
SELECT is(
    sweep_reserved_to_queue(1000),
    3,
    'sweep returns count of 3 swept slots'
);

-- 3. All swept slots have queued_at set
SELECT is(
    (SELECT COUNT(*)::INT FROM inventory_slots WHERE pool_id = 'sweep_test_pool' AND queued_at IS NOT NULL),
    3,
    'all swept slots have queued_at set'
);

-- 4. Messages exist in the queue
SELECT ok(
    (SELECT queue_length FROM pgmq.metrics('intake_queue')) >= 3,
    'messages exist in intake_queue after sweep'
);

-- 5. Second sweep returns 0 (idempotent)
SELECT is(
    sweep_reserved_to_queue(1000),
    0,
    'second sweep returns 0 (idempotent)'
);

-- 6. Sweep respects batch limit: add 3 more unqueued slots, sweep with limit 2
INSERT INTO inventory_slots (pool_id, status, locked_by, locked_at, queued_at)
VALUES
    ('sweep_test_pool', 'RESERVED', 'user_d', now() - interval '1 minute', NULL),
    ('sweep_test_pool', 'RESERVED', 'user_e', now() - interval '2 minutes', NULL),
    ('sweep_test_pool', 'RESERVED', 'user_f', now() - interval '3 minutes', NULL);

SELECT is(
    sweep_reserved_to_queue(2),
    2,
    'sweep respects batch limit of 2'
);

-- 7. Remaining slots stay unqueued after batch limit
SELECT is(
    (SELECT COUNT(*)::INT FROM inventory_slots WHERE pool_id = 'sweep_test_pool' AND queued_at IS NULL),
    1,
    'one slot remains unqueued after batch limit'
);

SELECT finish();
ROLLBACK;
