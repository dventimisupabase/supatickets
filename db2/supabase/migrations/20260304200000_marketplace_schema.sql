-- db2/supabase/migrations/20260304200000_marketplace_schema.sql
-- Marketplace tables: events, tickets, cart, orders.

-- Ticket status enum
CREATE TYPE ticket_status AS ENUM ('AVAILABLE', 'RESERVED', 'SOLD');

-- Events catalog
CREATE TABLE events (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL,
    description  TEXT,
    date         TIMESTAMPTZ NOT NULL,
    venue        TEXT NOT NULL,
    location     TEXT NOT NULL,
    image_url    TEXT,
    ticket_price NUMERIC(10,2) NOT NULL,
    total_tickets INT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Individual ticket inventory (one row per ticket)
CREATE TABLE event_tickets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    status      ticket_status NOT NULL DEFAULT 'AVAILABLE',
    reserved_by UUID REFERENCES auth.users(id),
    reserved_at TIMESTAMPTZ,
    seq_pos     INT
);

-- Index for claim queries: find AVAILABLE tickets by event
CREATE INDEX idx_event_tickets_available
    ON event_tickets (event_id, status)
    WHERE status = 'AVAILABLE';

-- Index for reaper: find expired reservations
CREATE INDEX idx_event_tickets_reserved
    ON event_tickets (reserved_at)
    WHERE status = 'RESERVED';

-- Shopping cart
CREATE TABLE cart_items (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_id     UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    ticket_count INT NOT NULL CHECK (ticket_count > 0),
    expires_at   TIMESTAMPTZ NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, event_id)  -- one cart entry per event per user
);

-- Orders (completed purchases)
CREATE TABLE orders (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES auth.users(id),
    total_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Order line items
CREATE TABLE order_items (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id     UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    event_id     UUID NOT NULL REFERENCES events(id),
    ticket_count INT NOT NULL,
    unit_price   NUMERIC(10,2) NOT NULL
);

-- === RLS ===

-- Events: public read
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "events are publicly readable"
    ON events FOR SELECT USING (true);

-- Event tickets: public read (for availability counts)
ALTER TABLE event_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tickets are publicly readable"
    ON event_tickets FOR SELECT USING (true);

-- Cart items: users see/manage only their own
ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users manage own cart"
    ON cart_items FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Orders: users see only their own
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users view own orders"
    ON orders FOR SELECT
    USING (auth.uid() = user_id);

-- Order items: users see only items in their orders
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users view own order items"
    ON order_items FOR SELECT
    USING (order_id IN (SELECT id FROM orders WHERE user_id = auth.uid()));
