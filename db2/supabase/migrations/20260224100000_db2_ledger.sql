-- db2/supabase/migrations/20260224100000_db2_ledger.sql

-- Confirmed tickets (permanent ledger)
CREATE TABLE confirmed_tickets (
    resource_id  UUID PRIMARY KEY,
    pool_id      TEXT NOT NULL,
    user_id      TEXT NOT NULL,
    confirmed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable Realtime for user-facing confirmation subscriptions
ALTER PUBLICATION supabase_realtime ADD TABLE confirmed_tickets;

-- Row Level Security: users can only see their own tickets
ALTER TABLE confirmed_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can view own tickets"
    ON confirmed_tickets FOR SELECT
    USING (auth.uid()::text = user_id);

-- finalize_transaction: idempotent insert (called by bridge worker)
-- Does NOT touch inventory_slots — that lives on DB1
CREATE OR REPLACE FUNCTION finalize_transaction(
    p_payload JSONB
) RETURNS VOID AS $$
BEGIN
    INSERT INTO confirmed_tickets (resource_id, pool_id, user_id)
    VALUES (
        (p_payload->>'resource_id')::uuid,
        p_payload->>'pool_id',
        p_payload->>'user_id'
    )
    ON CONFLICT (resource_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
