-- db1/supabase/migrations/20260224100001_intake_engine_functions.sql

-- 1. claim_resource_and_queue: SKIP LOCKED intake function
CREATE OR REPLACE FUNCTION claim_resource_and_queue(
    p_pool_id TEXT,
    p_user_id TEXT
) RETURNS UUID AS $$
DECLARE
    claimed_slot_id UUID;
    payload JSONB;
BEGIN
    UPDATE inventory_slots
    SET
        status    = 'RESERVED',
        locked_by = p_user_id,
        locked_at = NOW()
    WHERE id = (
        SELECT id
        FROM inventory_slots
        WHERE pool_id = p_pool_id
          AND status = 'AVAILABLE'
        LIMIT 1
        FOR UPDATE SKIP LOCKED
    )
    RETURNING id INTO claimed_slot_id;

    IF claimed_slot_id IS NOT NULL THEN
        payload := jsonb_build_object(
            'pool_id',     p_pool_id,
            'resource_id', claimed_slot_id,
            'user_id',     p_user_id,
            'state',       'queued'
        );
        PERFORM pgmq.send('intake_queue', payload);
    END IF;

    RETURN claimed_slot_id;
END;
$$ LANGUAGE plpgsql;

-- 2. intake_queue_read: PostgREST-compatible RPC wrapper for pgmq.read
CREATE OR REPLACE FUNCTION intake_queue_read(
    p_visibility_timeout INT,
    p_batch_size         INT
) RETURNS TABLE (
    msg_id      BIGINT,
    read_ct     INT,
    enqueued_at TIMESTAMPTZ,
    vt          TIMESTAMPTZ,
    message     JSONB
) AS $$
    SELECT msg_id, read_ct, enqueued_at, vt, message
    FROM pgmq.read('intake_queue', p_visibility_timeout, p_batch_size);
$$ LANGUAGE sql;

-- 3. intake_queue_delete: PostgREST-compatible RPC wrapper for pgmq.delete
CREATE OR REPLACE FUNCTION intake_queue_delete(
    p_msg_ids BIGINT[]
) RETURNS SETOF BIGINT AS $$
    SELECT * FROM pgmq.delete('intake_queue', p_msg_ids);
$$ LANGUAGE sql;

-- 4. intake_queue_send: PostgREST-compatible RPC wrapper for pgmq.send
CREATE OR REPLACE FUNCTION intake_queue_send(
    p_payload JSONB
) RETURNS BIGINT AS $$
    SELECT pgmq.send('intake_queue', p_payload);
$$ LANGUAGE sql;

-- 5. intake_route_to_dlq: move a message from intake_queue to intake_dlq
CREATE OR REPLACE FUNCTION intake_route_to_dlq(
    p_msg_id  BIGINT,
    p_payload JSONB,
    p_read_ct INT
) RETURNS BIGINT AS $$
DECLARE
    enriched_payload JSONB;
    dlq_msg_id       BIGINT;
BEGIN
    enriched_payload := p_payload || jsonb_build_object(
        'original_msg_id',  p_msg_id,
        'final_read_ct',    p_read_ct,
        'routed_to_dlq_at', now()
    );
    SELECT pgmq.send('intake_dlq', enriched_payload) INTO dlq_msg_id;
    PERFORM pgmq.delete('intake_queue', ARRAY[p_msg_id]);
    RETURN dlq_msg_id;
END;
$$ LANGUAGE plpgsql;

-- 6. snapshot_engine_metrics: fixed to iterate all active pools (not hardcoded)
CREATE OR REPLACE FUNCTION snapshot_engine_metrics() RETURNS VOID AS $$
DECLARE
    r              engine_config%ROWTYPE;
    v_available    INT;
    v_reserved     INT;
    v_consumed     INT;
    v_queue_depth  INT;
    v_dlq_depth    INT;
BEGIN
    FOR r IN SELECT * FROM engine_config WHERE is_active = true LOOP
        SELECT
            COUNT(*) FILTER (WHERE status = 'AVAILABLE'),
            COUNT(*) FILTER (WHERE status = 'RESERVED'),
            COUNT(*) FILTER (WHERE status = 'CONSUMED')
        INTO v_available, v_reserved, v_consumed
        FROM inventory_slots
        WHERE pool_id = r.pool_id;

        SELECT queue_length INTO v_queue_depth FROM pgmq.metrics('intake_queue');
        SELECT queue_length INTO v_dlq_depth   FROM pgmq.metrics('intake_dlq');

        INSERT INTO engine_metrics
            (pool_id, available_slots, reserved_slots, consumed_slots, queue_depth, dlq_depth)
        VALUES
            (r.pool_id, v_available, v_reserved, v_consumed, v_queue_depth, v_dlq_depth);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
