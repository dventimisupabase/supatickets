-- SupaTickets: Row Level Security
-- Run this after 01-schema.sql. Nothing here is application code: these
-- policies run inside Postgres itself, so there's no API layer to bypass.
--
-- PostgREST doesn't surface policy comments in its OpenAPI docs today,
-- but COMMENT ON keeps this file consistent with the rest of the schema.

ALTER TABLE events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "events are publicly readable"
    ON events FOR SELECT USING (true);

COMMENT ON POLICY "events are publicly readable" ON events IS
    'Anyone, signed in or not, can browse the events catalog.';

ALTER TABLE event_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tickets are publicly readable"
    ON event_tickets FOR SELECT USING (true);

COMMENT ON POLICY "tickets are publicly readable" ON event_tickets IS
    'Anyone can see ticket availability and status.';

ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users manage own cart"
    ON cart_items FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

COMMENT ON POLICY "users manage own cart" ON cart_items IS
    'Users can only see and modify their own cart items.';

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users view own orders"
    ON orders FOR SELECT
    USING (auth.uid() = user_id);

COMMENT ON POLICY "users view own orders" ON orders IS
    'Users can only see their own orders.';

ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users view own order items"
    ON order_items FOR SELECT
    USING (order_id IN (SELECT id FROM orders WHERE user_id = auth.uid()));

COMMENT ON POLICY "users view own order items" ON order_items IS
    'Users can only see line items belonging to their own orders.';
