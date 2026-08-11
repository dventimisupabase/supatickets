-- db1/supabase/migrations/20260224100004_grant_rpc_permissions.sql
-- Make RPC-callable functions run as owner so PostgREST callers don't need
-- direct access to the pgmq schema.

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
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION intake_queue_delete(
    p_msg_ids BIGINT[]
) RETURNS SETOF BIGINT AS $$
    SELECT * FROM pgmq.delete('intake_queue', p_msg_ids);
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION intake_queue_send(
    p_payload JSONB
) RETURNS BIGINT AS $$
    SELECT pgmq.send('intake_queue', p_payload);
$$ LANGUAGE sql SECURITY DEFINER;

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
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION intake_dlq_read(
    p_batch_size INT DEFAULT 100
) RETURNS TABLE (
    msg_id      BIGINT,
    read_ct     INT,
    enqueued_at TIMESTAMPTZ,
    vt          TIMESTAMPTZ,
    message     JSONB
) AS $$
    SELECT msg_id, read_ct, enqueued_at, vt, message
    FROM pgmq.read('intake_dlq', 30, p_batch_size);
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION intake_dlq_delete(
    p_msg_ids BIGINT[]
) RETURNS SETOF BIGINT AS $$
    SELECT * FROM pgmq.delete('intake_dlq', p_msg_ids);
$$ LANGUAGE sql SECURITY DEFINER;
