-- db2/supabase/tests/00002_marketplace.test.sql
BEGIN;
SELECT plan(20);

-- === Schema tests ===

SELECT has_table('events', 'events table exists');
SELECT has_table('event_tickets', 'event_tickets table exists');
SELECT has_table('cart_items', 'cart_items table exists');
SELECT has_table('orders', 'orders table exists');
SELECT has_table('order_items', 'order_items table exists');

-- === Function tests ===

SELECT has_function('claim_tickets', 'claim_tickets function exists');
SELECT has_function('unclaim_tickets', 'unclaim_tickets function exists');
SELECT has_function('checkout_cart', 'checkout_cart function exists');
SELECT has_function('get_event_availability', 'get_event_availability function exists');
SELECT has_function('reap_expired_reservations', 'reap_expired_reservations function exists');

-- === Seed test data (as postgres, before switching role) ===

-- Create a test user in auth.users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, role, aud, instance_id)
VALUES (
    'a0000000-0000-0000-0000-000000000001'::uuid,
    'test@example.com',
    crypt('password', gen_salt('bf')),
    now(),
    'authenticated',
    'authenticated',
    '00000000-0000-0000-0000-000000000000'::uuid
);

-- Create a test event (insert as postgres to bypass RLS)
INSERT INTO events (id, name, description, date, venue, location, ticket_price, total_tickets)
VALUES (
    'e0000000-0000-0000-0000-000000000001'::uuid,
    'Test Concert',
    'A test event',
    '2026-07-01'::timestamptz,
    'Test Arena',
    'Test City',
    50.00,
    5
);

-- Create 5 tickets (insert as postgres to bypass RLS)
INSERT INTO event_tickets (event_id, seq_pos)
SELECT 'e0000000-0000-0000-0000-000000000001'::uuid, generate_series(1, 5);

-- Now switch to authenticated role for function tests
SELECT set_config('request.jwt.claims',
    '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SELECT set_config('role', 'authenticated', true);

-- === get_event_availability ===

SELECT is(
    get_event_availability('e0000000-0000-0000-0000-000000000001'::uuid),
    5,
    'get_event_availability returns 5 for 5 available tickets'
);

-- === claim_tickets: success ===

SELECT is(
    array_length(claim_tickets('e0000000-0000-0000-0000-000000000001'::uuid, 2), 1),
    2,
    'claim_tickets returns 2 UUIDs when claiming 2 tickets'
);

SELECT is(
    get_event_availability('e0000000-0000-0000-0000-000000000001'::uuid),
    3,
    'availability decreases to 3 after claiming 2'
);

-- Verify cart item was created
SELECT is(
    (SELECT ticket_count FROM cart_items
     WHERE user_id = 'a0000000-0000-0000-0000-000000000001'::uuid
       AND event_id = 'e0000000-0000-0000-0000-000000000001'::uuid),
    2,
    'cart_items entry created with ticket_count=2'
);

-- === claim_tickets: all-or-nothing (request 4, only 3 available) ===

SELECT is(
    claim_tickets('e0000000-0000-0000-0000-000000000001'::uuid, 4),
    NULL::uuid[],
    'claim_tickets returns NULL when requesting more than available (all-or-nothing)'
);

-- === unclaim_tickets ===

SELECT is(
    unclaim_tickets('e0000000-0000-0000-0000-000000000001'::uuid),
    2,
    'unclaim_tickets releases 2 tickets'
);

SELECT is(
    get_event_availability('e0000000-0000-0000-0000-000000000001'::uuid),
    5,
    'availability returns to 5 after unclaim'
);

-- === checkout_cart ===

-- Claim 1 ticket, then checkout
SELECT claim_tickets('e0000000-0000-0000-0000-000000000001'::uuid, 1);

SELECT isnt(
    checkout_cart(),
    NULL::uuid,
    'checkout_cart returns a non-NULL order ID'
);

SELECT is(
    get_event_availability('e0000000-0000-0000-0000-000000000001'::uuid),
    4,
    'availability is 4 after checkout (1 ticket SOLD)'
);

-- Verify order was created
SELECT is(
    (SELECT total_amount FROM orders
     WHERE user_id = 'a0000000-0000-0000-0000-000000000001'::uuid
     ORDER BY created_at DESC LIMIT 1),
    50.00::numeric(10,2),
    'order total_amount is 50.00 (1 ticket * $50)'
);

SELECT finish();
ROLLBACK;
