-- SupaTickets: schema
-- Paste this into your Supabase project's SQL Editor and hit Run.
-- Just the data model: events, ticket inventory, carts, and orders.
--
-- Notice these use COMMENT ON instead of -- comments: PostgREST reads
-- them straight into the auto-generated OpenAPI docs for this project.

CREATE TYPE ticket_status AS ENUM ('AVAILABLE', 'RESERVED', 'SOLD');

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
COMMENT ON TABLE events IS 'Events catalog.';

CREATE TABLE event_tickets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    status      ticket_status NOT NULL DEFAULT 'AVAILABLE',
    reserved_by UUID REFERENCES auth.users(id),
    reserved_at TIMESTAMPTZ,
    seq_pos     INT
);
COMMENT ON TABLE event_tickets IS 'Individual ticket inventory: one row per physical ticket.';

CREATE TABLE cart_items (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_id     UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    ticket_count INT NOT NULL CHECK (ticket_count > 0),
    expires_at   TIMESTAMPTZ NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT one_cart_entry_per_event UNIQUE (user_id, event_id)
);
COMMENT ON TABLE cart_items IS 'Shopping cart.';
COMMENT ON CONSTRAINT one_cart_entry_per_event ON cart_items IS 'One cart entry per event per user.';

CREATE TABLE orders (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES auth.users(id),
    total_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE orders IS 'Orders: completed purchases.';

CREATE TABLE order_items (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id     UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    event_id     UUID NOT NULL REFERENCES events(id),
    ticket_count INT NOT NULL,
    unit_price   NUMERIC(10,2) NOT NULL
);
COMMENT ON TABLE order_items IS 'Order line items.';
