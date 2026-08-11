-- SupaTickets: Row Level Security
-- Run this after 01-schema.sql. Nothing here is application code: these
-- policies run inside Postgres itself, so there's no API layer to bypass.
-- Events and ticket availability are public. Carts and orders are
-- visible only to the user who owns them.

ALTER TABLE events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "events are publicly readable"
    ON events FOR SELECT USING (true);

ALTER TABLE event_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tickets are publicly readable"
    ON event_tickets FOR SELECT USING (true);

ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users manage own cart"
    ON cart_items FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users view own orders"
    ON orders FOR SELECT
    USING (auth.uid() = user_id);

ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users view own order items"
    ON order_items FOR SELECT
    USING (order_id IN (SELECT id FROM orders WHERE user_id = auth.uid()));
