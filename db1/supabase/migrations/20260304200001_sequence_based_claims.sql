-- db1/supabase/migrations/20260304200001_sequence_based_claims.sql
-- Replace SKIP LOCKED scan with sequence-based O(1) claiming.
-- Drops partial indexes to enable HOT updates on the claim path.

-- (a) Sequential position column
ALTER TABLE inventory_slots ADD COLUMN seq_pos BIGINT;

-- (b) Direct lookup index (replaces partial index scan)
CREATE UNIQUE INDEX idx_slots_pool_seq
    ON inventory_slots (pool_id, seq_pos)
    WHERE seq_pos IS NOT NULL;

-- (c) Drop partial indexes — no longer needed for claims;
--     sweep/reaper can seq-scan a fully-cached UNLOGGED table
DROP INDEX IF EXISTS idx_available_slots;
DROP INDEX IF EXISTS idx_reserved_unqueued_slots;

-- (d) Fillfactor: leave room for HOT tuple copies
ALTER TABLE inventory_slots SET (fillfactor = 50);

-- (e) Helper: assign sequential positions to AVAILABLE slots in a pool
CREATE OR REPLACE FUNCTION assign_seq_positions(p_pool_id TEXT) RETURNS INT AS $$
DECLARE
    cnt INT;
BEGIN
    WITH numbered AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn
        FROM inventory_slots
        WHERE pool_id = p_pool_id AND status = 'AVAILABLE'
    )
    UPDATE inventory_slots s
    SET seq_pos = n.rn
    FROM numbered n
    WHERE s.id = n.id;

    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- (f) Helper: create/reset claim sequence for a pool
CREATE OR REPLACE FUNCTION reset_claim_sequence(
    p_pool_id TEXT,
    p_start BIGINT DEFAULT 1
) RETURNS VOID AS $$
BEGIN
    EXECUTE format(
        'CREATE SEQUENCE IF NOT EXISTS %I START %s',
        'claim_seq_' || p_pool_id, p_start
    );
    EXECUTE format(
        'ALTER SEQUENCE %I RESTART WITH %s',
        'claim_seq_' || p_pool_id, p_start
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- (g) Rewrite claim: sequence-based O(1) + HOT-eligible UPDATE
CREATE OR REPLACE FUNCTION claim_resource_and_queue(
    p_pool_id TEXT,
    p_user_id TEXT
) RETURNS UUID AS $$
DECLARE
    pos BIGINT;
    claimed_slot_id UUID;
BEGIN
    -- O(1): atomically grab next position
    pos := nextval('claim_seq_' || p_pool_id);

    -- Direct index lookup on (pool_id, seq_pos); HOT-eligible update
    UPDATE inventory_slots
    SET status    = 'RESERVED',
        locked_by = p_user_id,
        locked_at = NOW()
    WHERE pool_id = p_pool_id
      AND seq_pos = pos
    RETURNING id INTO claimed_slot_id;

    -- NULL if pos > slot count (sold out)
    RETURN claimed_slot_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
