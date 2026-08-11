-- SupaTickets: indexes
-- Run this after 03-functions.sql. Everything already works without these,
-- they just keep claim_tickets and the reaper fast as event_tickets grows.
-- Partial indexes: only the rows the hot paths actually query.

CREATE INDEX idx_event_tickets_available
    ON event_tickets (event_id, status)
    WHERE status = 'AVAILABLE';

CREATE INDEX idx_event_tickets_reserved
    ON event_tickets (reserved_at)
    WHERE status = 'RESERVED';
