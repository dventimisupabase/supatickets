-- SupaTickets: indexes
-- Run this after 03-functions.sql. Everything already works without these,
-- they just keep claim_tickets and the reaper fast as event_tickets grows.

CREATE INDEX idx_event_tickets_available ON event_tickets (event_id, status) WHERE status = 'AVAILABLE';
COMMENT ON INDEX idx_event_tickets_available IS 'Partial index backing claim_tickets: only rows worth scanning when looking for AVAILABLE tickets.';

CREATE INDEX idx_event_tickets_reserved ON event_tickets (reserved_at) WHERE status = 'RESERVED';
COMMENT ON INDEX idx_event_tickets_reserved IS 'Partial index backing reap_expired_reservations: only rows worth scanning when looking for expired RESERVED tickets.';
