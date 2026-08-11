-- db1/supabase/tests/00001_intake_tables.test.sql
BEGIN;
SELECT plan(20);

-- Extensions
SELECT has_extension('pgmq', 'pgmq extension exists');
SELECT has_extension('pg_cron', 'pg_cron extension exists');
SELECT has_extension('pg_net', 'pg_net extension exists');

-- Enum type
SELECT has_type('slot_status', 'slot_status enum exists');
SELECT enum_has_labels('slot_status', ARRAY['AVAILABLE', 'RESERVED', 'CONSUMED'], 'slot_status has correct labels');

-- inventory_slots table
SELECT has_table('inventory_slots', 'inventory_slots table exists');
SELECT has_column('inventory_slots', 'id', 'inventory_slots has id');
SELECT has_column('inventory_slots', 'pool_id', 'inventory_slots has pool_id');
SELECT has_column('inventory_slots', 'status', 'inventory_slots has status');
SELECT has_column('inventory_slots', 'locked_by', 'inventory_slots has locked_by');
SELECT has_column('inventory_slots', 'locked_at', 'inventory_slots has locked_at');
SELECT has_column('inventory_slots', 'queued_at', 'inventory_slots has queued_at');

-- engine_config table
SELECT has_table('engine_config', 'engine_config table exists');
SELECT has_column('engine_config', 'visibility_timeout_sec', 'engine_config has visibility_timeout_sec');
SELECT has_column('engine_config', 'commit_webhook_url', 'engine_config has commit_webhook_url');

-- engine_metrics table
SELECT has_table('engine_metrics', 'engine_metrics table exists');
SELECT col_is_pk('engine_metrics', 'id', 'engine_metrics has PK');
SELECT has_index('engine_metrics', 'idx_metrics_pool_ts', 'engine_metrics has pool/ts index');

-- pgmq queues
SELECT ok(
    (SELECT EXISTS (SELECT 1 FROM pgmq.list_queues() WHERE queue_name = 'intake_queue')),
    'intake_queue exists'
);
SELECT ok(
    (SELECT EXISTS (SELECT 1 FROM pgmq.list_queues() WHERE queue_name = 'intake_dlq')),
    'intake_dlq exists'
);

SELECT finish();
ROLLBACK;
