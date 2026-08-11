-- db1/supabase/tests/00003_intake_cron.test.sql
BEGIN;
SELECT plan(5);

-- reap_orphaned_slots function exists
SELECT has_function('reap_orphaned_slots', 'reap_orphaned_slots function exists');

-- Setup: an orphaned RESERVED slot (no matching queue message, older than threshold)
INSERT INTO engine_config (pool_id, batch_size, visibility_timeout_sec, max_retries, is_active)
VALUES ('reap_test_pool', 10, 45, 3, true)
ON CONFLICT (pool_id) DO NOTHING;

INSERT INTO inventory_slots (id, pool_id, status, locked_by, locked_at, queued_at)
VALUES (
    '00000000-0000-0000-0000-000000000001'::uuid,
    'reap_test_pool',
    'RESERVED',
    'stale_user',
    now() - interval '20 minutes',
    now() - interval '20 minutes'
);

-- Orphaned slot (no matching queue message) should be reaped
SELECT ok(
    reap_orphaned_slots(interval '10 minutes') >= 1,
    'reap_orphaned_slots reaps stale orphaned slots'
);

SELECT is(
    (SELECT status FROM inventory_slots WHERE id = '00000000-0000-0000-0000-000000000001'::uuid),
    'AVAILABLE'::slot_status,
    'reaped slot status is reset to AVAILABLE'
);

SELECT is(
    (SELECT locked_by FROM inventory_slots WHERE id = '00000000-0000-0000-0000-000000000001'::uuid),
    NULL,
    'reaped slot locked_by is cleared'
);

-- A RESERVED slot with a matching queue message should NOT be reaped
INSERT INTO inventory_slots (id, pool_id, status, locked_by, locked_at, queued_at)
VALUES (
    '00000000-0000-0000-0000-000000000002'::uuid,
    'reap_test_pool',
    'RESERVED',
    'active_user',
    now() - interval '20 minutes',
    now() - interval '20 minutes'
);

-- Enqueue a message referencing this slot
SELECT pgmq.send('intake_queue',
    jsonb_build_object('resource_id', '00000000-0000-0000-0000-000000000002', 'pool_id', 'reap_test_pool', 'user_id', 'active_user', 'state', 'queued')
);

SELECT ok(
    (SELECT status FROM inventory_slots WHERE id = '00000000-0000-0000-0000-000000000002'::uuid) = 'RESERVED'::slot_status,
    'slot with active queue message is NOT reaped'
);

SELECT finish();
ROLLBACK;
