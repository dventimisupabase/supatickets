-- db1/supabase/seed.sql

-- Demo pool config
INSERT INTO engine_config (pool_id, batch_size, visibility_timeout_sec, max_retries, is_active)
VALUES ('demo_concert_2026', 100, 45, 10, true);

-- 1000 available tickets
INSERT INTO inventory_slots (pool_id, status)
SELECT 'demo_concert_2026', 'AVAILABLE'
FROM generate_series(1, 1000);
