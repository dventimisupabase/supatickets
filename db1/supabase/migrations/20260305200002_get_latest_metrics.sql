-- Expose latest engine_metrics snapshot per pool via PostgREST RPC.
-- SECURITY DEFINER so anon role can call it.

CREATE OR REPLACE FUNCTION get_latest_metrics()
RETURNS TABLE (
    pool_id TEXT,
    captured_at TIMESTAMPTZ,
    available_slots INT,
    reserved_slots INT,
    consumed_slots INT,
    queue_depth INT,
    dlq_depth INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (em.pool_id)
        em.pool_id,
        em.captured_at,
        em.available_slots,
        em.reserved_slots,
        em.consumed_slots,
        em.queue_depth,
        em.dlq_depth
    FROM engine_metrics em
    ORDER BY em.pool_id, em.captured_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
