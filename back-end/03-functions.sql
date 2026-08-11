-- SupaTickets: business logic
-- Run this after 02-rls.sql. Every one of these is a plain Postgres
-- function called over RPC from the front end, no application server involved.
--
-- Each COMMENT ON FUNCTION becomes that endpoint's description in the
-- OpenAPI docs PostgREST generates for this project, not just a note
-- for whoever reads the SQL.

CREATE OR REPLACE FUNCTION claim_tickets(
    p_event_id UUID,
    p_count    INT
) RETURNS UUID[] AS $$
DECLARE
    v_user_id  UUID := auth.uid();
    v_claimed  UUID[];
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- Lock and select p_count AVAILABLE tickets. SKIP LOCKED lets concurrent
    -- buyers claim different rows instead of queuing behind each other.
    SELECT ARRAY_AGG(id) INTO v_claimed
    FROM (
        SELECT id FROM event_tickets
        WHERE event_id = p_event_id AND status = 'AVAILABLE'
        ORDER BY seq_pos
        FOR UPDATE SKIP LOCKED
        LIMIT p_count
    ) sub;

    -- All-or-nothing: if fewer than requested, return NULL
    IF v_claimed IS NULL OR array_length(v_claimed, 1) < p_count THEN
        RETURN NULL;
    END IF;

    -- Reserve the tickets
    UPDATE event_tickets
    SET status      = 'RESERVED',
        reserved_by = v_user_id,
        reserved_at = NOW()
    WHERE id = ANY(v_claimed);

    -- Insert cart item (upsert: if user already has this event, update count)
    INSERT INTO cart_items (user_id, event_id, ticket_count, expires_at)
    VALUES (v_user_id, p_event_id, p_count, NOW() + INTERVAL '20 minutes')
    ON CONFLICT (user_id, event_id) DO UPDATE
    SET ticket_count = cart_items.ticket_count + EXCLUDED.ticket_count,
        expires_at   = NOW() + INTERVAL '20 minutes';

    RETURN v_claimed;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION claim_tickets(UUID, INT) IS
    'All-or-nothing batch claim. Returns the claimed ticket IDs, or NULL if not enough inventory is available.';

CREATE OR REPLACE FUNCTION unclaim_tickets(
    p_event_id UUID
) RETURNS INT AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_count   INT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    UPDATE event_tickets
    SET status      = 'AVAILABLE',
        reserved_by = NULL,
        reserved_at = NULL
    WHERE event_id    = p_event_id
      AND reserved_by = v_user_id
      AND status      = 'RESERVED';

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Remove cart item
    DELETE FROM cart_items
    WHERE user_id = v_user_id AND event_id = p_event_id;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION unclaim_tickets(UUID) IS
    'Releases reserved tickets for the caller and event. Returns the number of tickets released.';

CREATE OR REPLACE FUNCTION checkout_cart()
RETURNS UUID AS $$
DECLARE
    v_user_id  UUID := auth.uid();
    v_order_id UUID;
    v_total    NUMERIC(10,2) := 0;
    v_item     RECORD;
    v_has_items BOOLEAN := FALSE;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- Create order
    INSERT INTO orders (user_id, total_amount)
    VALUES (v_user_id, 0)
    RETURNING id INTO v_order_id;

    -- Process each non-expired cart item
    FOR v_item IN
        SELECT ci.id AS cart_item_id, ci.event_id, ci.ticket_count, e.ticket_price
        FROM cart_items ci
        JOIN events e ON e.id = ci.event_id
        WHERE ci.user_id = v_user_id
          AND ci.expires_at > NOW()
    LOOP
        v_has_items := TRUE;

        -- Create order line item
        INSERT INTO order_items (order_id, event_id, ticket_count, unit_price)
        VALUES (v_order_id, v_item.event_id, v_item.ticket_count, v_item.ticket_price);

        -- Mark tickets as SOLD
        UPDATE event_tickets
        SET status = 'SOLD'
        WHERE event_id    = v_item.event_id
          AND reserved_by = v_user_id
          AND status      = 'RESERVED';

        v_total := v_total + (v_item.ticket_count * v_item.ticket_price);
    END LOOP;

    -- Update order total
    UPDATE orders SET total_amount = v_total WHERE id = v_order_id;

    -- Clear cart
    DELETE FROM cart_items WHERE user_id = v_user_id;

    -- If no valid items, delete the empty order
    IF NOT v_has_items THEN
        DELETE FROM orders WHERE id = v_order_id;
        RETURN NULL;
    END IF;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION checkout_cart() IS
    'Creates an order from the caller''s non-expired cart items. Returns the new order ID, or NULL if the cart is empty or expired.';

CREATE OR REPLACE FUNCTION get_event_availability(p_event_id UUID)
RETURNS INT AS $$
    SELECT COUNT(*)::INT FROM event_tickets
    WHERE event_id = p_event_id AND status = 'AVAILABLE';
$$ LANGUAGE sql SECURITY DEFINER STABLE;

COMMENT ON FUNCTION get_event_availability(UUID) IS
    'Counts AVAILABLE tickets for an event.';

CREATE OR REPLACE FUNCTION reap_expired_reservations()
RETURNS INT AS $$
DECLARE
    v_count INT;
BEGIN
    -- Release expired tickets
    UPDATE event_tickets
    SET status      = 'AVAILABLE',
        reserved_by = NULL,
        reserved_at = NULL
    WHERE status = 'RESERVED'
      AND reserved_at < NOW() - INTERVAL '20 minutes';

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Clean up expired cart items
    DELETE FROM cart_items WHERE expires_at <= NOW();

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION reap_expired_reservations() IS
    'Releases tickets reserved more than 20 minutes ago. The safety net for carts abandoned mid-checkout.';

-- Give it its own heartbeat: one line of SQL and pg_cron runs the reaper
-- every minute, no server, no infrastructure, just Postgres.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

SELECT cron.schedule(
    'reap-expired-reservations',
    '* * * * *',
    $$SELECT reap_expired_reservations()$$
);
