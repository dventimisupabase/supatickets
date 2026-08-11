-- SupaTickets: schema
-- Paste this into your Supabase project's SQL Editor and hit Run.
-- Just the data model: events, ticket inventory, carts, and orders.

CREATE TYPE ticket_status AS ENUM ('AVAILABLE', 'RESERVED', 'SOLD');

-- Events catalog
CREATE TABLE events (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL,
    description   TEXT,
    date          TIMESTAMPTZ NOT NULL,
    venue         TEXT NOT NULL,
    location      TEXT NOT NULL,
    image_url     TEXT,
    ticket_price  NUMERIC(10,2) NOT NULL,
    total_tickets INT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Individual ticket inventory: one row per physical ticket
CREATE TABLE event_tickets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    status      ticket_status NOT NULL DEFAULT 'AVAILABLE',
    reserved_by UUID REFERENCES auth.users(id),
    reserved_at TIMESTAMPTZ,
    seq_pos     INT
);

-- Partial indexes: only the rows the hot paths actually query
CREATE INDEX idx_event_tickets_available
    ON event_tickets (event_id, status)
    WHERE status = 'AVAILABLE';

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

-- Orders: completed purchases
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
