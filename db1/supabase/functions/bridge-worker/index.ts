// db1/supabase/functions/bridge-worker/index.ts
import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

// Module-level clients — never torn down between requests (Edge Function best practice)
const db1 = createClient(
    Deno.env.get('DB1_SUPABASE_URL')!,
    Deno.env.get('DB1_SUPABASE_SERVICE_ROLE_KEY')!
);

// db2 client is lazy — only used when pools use RPC mode (not webhook mode)
let db2: SupabaseClient | null = null;
function getDb2(): SupabaseClient {
    if (!db2) {
        db2 = createClient(
            Deno.env.get('DB2_SUPABASE_URL')!,
            Deno.env.get('DB2_SUPABASE_SERVICE_ROLE_KEY')!
        );
    }
    return db2;
}

interface QueueMessage {
    msg_id: number;
    read_ct: number;
    message: {
        pool_id: string;
        resource_id: string;
        user_id: string;
        state: 'queued' | 'validated' | 'committed';
    };
}

interface PoolConfig {
    batch_size: number;
    visibility_timeout_sec: number;
    max_retries: number;
    validation_webhook_url: string | null;
    commit_rpc_name: string;
    commit_webhook_url: string | null;
}

Deno.serve(async () => {
    const TIMEOUT_MS = 50_000;

    try {
        const result = await Promise.race([
            runWorker(),
            new Promise<never>((_, reject) =>
                setTimeout(() => reject(new Error('Worker timeout after 50s')), TIMEOUT_MS)
            ),
        ]);

        return new Response(JSON.stringify(result), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
        });
    } catch (err) {
        console.error(JSON.stringify({ level: 'fatal', error: String(err) }));
        return new Response('Internal Server Error', { status: 500 });
    }
});

async function runWorker(): Promise<object> {
    // Read pool configs (cached per invocation)
    const { data: configs, error: configErr } = await db1
        .from('engine_config')
        .select('*')
        .eq('is_active', true);

    if (configErr) throw new Error(`DB1 config read failed: ${configErr.message}`);
    if (!configs || configs.length === 0) return { status: 'idle', reason: 'no active pools' };

    const config = configs[0] as PoolConfig; // Use first active pool's settings for queue read
    const { batch_size, visibility_timeout_sec } = config;

    // Read queue
    const { data: messages, error: readErr } = await db1.rpc('intake_queue_read', {
        p_visibility_timeout: visibility_timeout_sec,
        p_batch_size: batch_size,
    });

    if (readErr) throw new Error(`DB1 queue read failed: ${readErr.message}`);
    if (!messages || messages.length === 0) return { status: 'idle', reason: 'queue empty' };

    const acked: number[] = [];
    let dlqCount = 0;

    for (const msg of messages as QueueMessage[]) {
        const { msg_id, read_ct, message: payload } = msg;
        const poolConfig = configs.find((c: PoolConfig & { pool_id: string }) => c.pool_id === payload.pool_id) ?? config;

        try {
            // Route to DLQ if exceeded max retries
            if (read_ct >= poolConfig.max_retries) {
                await db1.rpc('intake_route_to_dlq', {
                    p_msg_id: msg_id,
                    p_payload: payload,
                    p_read_ct: read_ct,
                });
                console.log(JSON.stringify({ level: 'warn', event: 'dlq', msg_id, pool_id: payload.pool_id }));
                dlqCount++;
                acked.push(msg_id); // already removed from queue by route_to_dlq
                continue;
            }

            // Validation webhook (only if state is 'queued')
            if (payload.state === 'queued' && poolConfig.validation_webhook_url) {
                const res = await fetch(poolConfig.validation_webhook_url, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Idempotency-Key': payload.resource_id,
                    },
                    body: JSON.stringify(payload),
                });
                if (!res.ok) throw new Error(`Validation webhook returned ${res.status}`);
                payload.state = 'validated';
            } else if (payload.state === 'queued') {
                payload.state = 'validated';
            }

            // Commit to DB2
            if (poolConfig.commit_webhook_url) {
                // Webhook mode (legacy DB2)
                const res = await fetch(poolConfig.commit_webhook_url, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Idempotency-Key': payload.resource_id,
                    },
                    body: JSON.stringify(payload),
                });
                if (!res.ok) throw new Error(`Commit webhook returned ${res.status}`);
            } else {
                // RPC mode (Supabase DB2)
                const { error: commitErr } = await getDb2().rpc(poolConfig.commit_rpc_name, {
                    p_payload: payload,
                });
                if (commitErr) throw new Error(`DB2 commit failed: ${commitErr.message}`);
            }

            // Update slot to CONSUMED on DB1
            await db1
                .from('inventory_slots')
                .update({ status: 'CONSUMED' })
                .eq('id', payload.resource_id)
                .eq('status', 'RESERVED');

            console.log(JSON.stringify({ level: 'info', event: 'committed', msg_id, pool_id: payload.pool_id }));
            acked.push(msg_id);

        } catch (err) {
            // DB2/webhook failure: leave message on queue for retry
            console.error(JSON.stringify({ level: 'error', event: 'processing_failed', msg_id, pool_id: payload.pool_id, error: String(err) }));
        }
    }

    // Batch delete acknowledged messages
    const toDelete = acked.filter(id => !dlqCount); // DLQ already deleted via route_to_dlq
    if (toDelete.length > 0) {
        await db1.rpc('intake_queue_delete', { p_msg_ids: toDelete });
    }

    return {
        status: 'success',
        processed: acked.length - dlqCount,
        dlq: dlqCount,
        total: messages.length,
    };
}
