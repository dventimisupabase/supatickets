-- SupaTickets: scheduled job
-- Run this after 02-functions.sql. One line of SQL gives reap_expired_reservations
-- its own heartbeat, no server, no infrastructure, just Postgres.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

SELECT cron.schedule(
    'reap-expired-reservations',
    '* * * * *',
    $$SELECT reap_expired_reservations()$$
);
