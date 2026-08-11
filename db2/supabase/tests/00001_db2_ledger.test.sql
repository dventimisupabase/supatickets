-- db2/supabase/tests/00001_db2_ledger.test.sql
BEGIN;
SELECT plan(8);

-- confirmed_tickets table exists
SELECT has_table('confirmed_tickets', 'confirmed_tickets table exists');
SELECT col_is_pk('confirmed_tickets', 'resource_id', 'confirmed_tickets PK is resource_id');
SELECT has_column('confirmed_tickets', 'pool_id', 'confirmed_tickets has pool_id');
SELECT has_column('confirmed_tickets', 'user_id', 'confirmed_tickets has user_id');
SELECT has_column('confirmed_tickets', 'confirmed_at', 'confirmed_tickets has confirmed_at');

-- finalize_transaction function exists
SELECT has_function('finalize_transaction', 'finalize_transaction function exists');

-- finalize_transaction inserts a row
SELECT finalize_transaction(
    '{"resource_id": "a0000000-0000-0000-0000-000000000001", "pool_id": "test_pool", "user_id": "user_42"}'::jsonb
);

SELECT is(
    (SELECT user_id FROM confirmed_tickets WHERE resource_id = 'a0000000-0000-0000-0000-000000000001'::uuid),
    'user_42',
    'finalize_transaction inserts correct user_id'
);

-- Idempotency: calling twice with same resource_id does not error, results in one row
SELECT finalize_transaction(
    '{"resource_id": "a0000000-0000-0000-0000-000000000001", "pool_id": "test_pool", "user_id": "user_42"}'::jsonb
);

SELECT is(
    (SELECT COUNT(*)::INT FROM confirmed_tickets WHERE resource_id = 'a0000000-0000-0000-0000-000000000001'::uuid),
    1,
    'finalize_transaction is idempotent (ON CONFLICT DO NOTHING)'
);

SELECT finish();
ROLLBACK;
