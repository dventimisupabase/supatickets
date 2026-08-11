-- db1/supabase/migrations/20260224100003_intake_dlq_wrappers.sql

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
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION intake_dlq_delete(
    p_msg_ids BIGINT[]
) RETURNS SETOF BIGINT AS $$
    SELECT * FROM pgmq.delete('intake_dlq', p_msg_ids);
$$ LANGUAGE sql;
