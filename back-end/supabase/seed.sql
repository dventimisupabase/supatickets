-- db2/supabase/seed.sql
-- Seed 6 events with ticket inventory for the marketplace demo.

INSERT INTO events (id, name, description, date, venue, location, image_url, ticket_price, total_tickets) VALUES
('e1000000-0000-0000-0000-000000000001', 'Kendrick Lamar — Grand Final Tour',
 'The Pulitzer Prize-winning artist brings his legendary catalog to the stage for one last time.',
 '2026-07-15 20:00:00-07', 'Allegiant Stadium', 'Las Vegas, NV',
 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=800&h=400&fit=crop',
 150.00, 50000),

('e2000000-0000-0000-0000-000000000002', 'Royal Shakespeare Company — Hamlet',
 'A bold new production of Shakespeare''s greatest tragedy, featuring an all-star ensemble cast.',
 '2026-05-20 19:30:00+01', 'Barbican Theatre', 'London, UK',
 'https://images.unsplash.com/photo-1503095396549-807759245b35?w=800&h=400&fit=crop',
 85.00, 800),

('e3000000-0000-0000-0000-000000000003', 'Taylor Swift — Eras Tour II',
 'She''s back. The biggest tour in history returns with new music, new production, new era.',
 '2026-09-01 19:00:00-07', 'SoFi Stadium', 'Los Angeles, CA',
 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=800&h=400&fit=crop',
 250.00, 20000),

('e4000000-0000-0000-0000-000000000004', 'Friday Night Jazz Quartet',
 'An intimate evening of classic jazz standards and original compositions.',
 '2026-04-18 21:00:00-04', 'Blue Note', 'New York, NY',
 'https://images.unsplash.com/photo-1511192336575-5a79af67a629?w=800&h=400&fit=crop',
 35.00, 200),

('e5000000-0000-0000-0000-000000000005', 'NBA Finals — Game 7',
 'The ultimate showdown. Two teams, one trophy, winner takes all.',
 '2026-06-22 18:00:00-07', 'Chase Center', 'San Francisco, CA',
 'https://images.unsplash.com/photo-1546519638-68e109498ffc?w=800&h=400&fit=crop',
 300.00, 18000),

('e6000000-0000-0000-0000-000000000006', 'Cirque du Soleil — Ethereal',
 'A breathtaking new spectacle blending acrobatics, dance, and immersive technology.',
 '2026-08-10 19:30:00+01', 'Royal Albert Hall', 'London, UK',
 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&h=400&fit=crop',
 120.00, 2500);

-- Generate ticket inventory for each event.
-- Uses generate_series to create one row per ticket.
INSERT INTO event_tickets (event_id, seq_pos)
SELECT e.id, gs.n
FROM events e
CROSS JOIN LATERAL generate_series(1, e.total_tickets) AS gs(n);
