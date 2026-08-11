-- SupaTickets: schema
-- Paste this into your Supabase project's SQL Editor and hit Run.
-- Just the data model: events, ticket inventory, carts, and orders.
--
-- Notice these use COMMENT ON instead of -- comments: PostgREST reads
-- them straight into the auto-generated OpenAPI docs for this project,
-- right down to individual columns.

CREATE TYPE ticket_status AS ENUM ('AVAILABLE', 'RESERVED', 'SOLD');
COMMENT ON TYPE ticket_status IS 'Lifecycle of a single ticket: AVAILABLE, RESERVED, or SOLD.';

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
COMMENT ON COLUMN events.id IS 'Unique event ID.';
COMMENT ON COLUMN events.name IS 'Event name, e.g. the artist, show, or team.';
COMMENT ON COLUMN events.description IS 'Longer blurb shown on the event page.';
COMMENT ON COLUMN events.date IS 'When the event happens.';
COMMENT ON COLUMN events.venue IS 'Venue name.';
COMMENT ON COLUMN events.location IS 'City and state or country.';
COMMENT ON COLUMN events.image_url IS 'Hero image shown on the event card.';
COMMENT ON COLUMN events.ticket_price IS 'Price per ticket, in USD.';
COMMENT ON COLUMN events.total_tickets IS 'How many tickets were minted into event_tickets when the event was seeded.';
COMMENT ON COLUMN events.created_at IS 'When the event was added to the catalog.';

CREATE TABLE event_tickets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    status      ticket_status NOT NULL DEFAULT 'AVAILABLE',
    reserved_by UUID REFERENCES auth.users(id),
    reserved_at TIMESTAMPTZ,
    seq_pos     INT
);
COMMENT ON TABLE event_tickets IS 'Individual ticket inventory: one row per physical ticket.';
COMMENT ON COLUMN event_tickets.id IS 'Unique ticket ID.';
COMMENT ON COLUMN event_tickets.event_id IS 'Which event this ticket belongs to.';
COMMENT ON COLUMN event_tickets.status IS 'AVAILABLE, RESERVED, or SOLD.';
COMMENT ON COLUMN event_tickets.reserved_by IS 'Who currently has this ticket reserved, if anyone.';
COMMENT ON COLUMN event_tickets.reserved_at IS 'When the reservation was made. reap_expired_reservations releases it after 20 minutes.';
COMMENT ON COLUMN event_tickets.seq_pos IS 'Claim order within the event, so claim_tickets hands out tickets in a stable order.';

-- Broadcast changes on this table over Realtime, so the front end can
-- show "tickets left" ticking down live instead of on a page refresh.
ALTER PUBLICATION supabase_realtime ADD TABLE event_tickets;

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
COMMENT ON COLUMN cart_items.id IS 'Unique cart line ID.';
COMMENT ON COLUMN cart_items.user_id IS 'Who this cart entry belongs to.';
COMMENT ON COLUMN cart_items.event_id IS 'Which event the reserved tickets are for.';
COMMENT ON COLUMN cart_items.ticket_count IS 'How many tickets are reserved in this entry.';
COMMENT ON COLUMN cart_items.expires_at IS 'Reservation deadline. checkout_cart ignores entries past this.';
COMMENT ON COLUMN cart_items.created_at IS 'When the reservation was first made.';

CREATE TABLE orders (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES auth.users(id),
    total_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE orders IS 'Orders: completed purchases.';
COMMENT ON COLUMN orders.id IS 'Unique order ID.';
COMMENT ON COLUMN orders.user_id IS 'Who placed the order.';
COMMENT ON COLUMN orders.total_amount IS 'Order total, in USD, computed at checkout.';
COMMENT ON COLUMN orders.created_at IS 'When the order was placed.';

CREATE TABLE order_items (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id     UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    event_id     UUID NOT NULL REFERENCES events(id),
    ticket_count INT NOT NULL,
    unit_price   NUMERIC(10,2) NOT NULL
);
COMMENT ON TABLE order_items IS 'Order line items.';
COMMENT ON COLUMN order_items.id IS 'Unique order line ID.';
COMMENT ON COLUMN order_items.order_id IS 'Which order this line belongs to.';
COMMENT ON COLUMN order_items.event_id IS 'Which event the tickets were for.';
COMMENT ON COLUMN order_items.ticket_count IS 'How many tickets were purchased in this line.';
COMMENT ON COLUMN order_items.unit_price IS 'Price per ticket at the time of purchase, copied from events.ticket_price so later price changes don''t rewrite history.';
