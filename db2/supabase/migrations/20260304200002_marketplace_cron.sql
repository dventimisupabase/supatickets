-- db2/supabase/migrations/20260304200002_marketplace_cron.sql
-- pg_cron job: reap expired reservations every minute.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

SELECT cron.schedule(
    'reap-expired-reservations',
    '* * * * *',
    $$SELECT reap_expired_reservations()$$
);
