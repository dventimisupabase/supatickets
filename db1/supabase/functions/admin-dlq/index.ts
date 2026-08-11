// db1/supabase/functions/admin-dlq/index.ts
import { createClient } from 'jsr:@supabase/supabase-js@2';

const db1 = createClient(
    Deno.env.get('DB1_SUPABASE_URL')!,
    Deno.env.get('DB1_SUPABASE_SERVICE_ROLE_KEY')!
);

Deno.serve(async (req) => {
    // Auth check
    const auth = req.headers.get('Authorization') ?? '';
    const serviceKey = Deno.env.get('DB1_SUPABASE_SERVICE_ROLE_KEY')!;
    if (auth !== `Bearer ${serviceKey}`) {
        return new Response('Unauthorized', { status: 401 });
    }

    const url = new URL(req.url);
    const method = req.method;

    // GET /admin-dlq?pool_id=X — list DLQ messages for a pool
    if (method === 'GET') {
        const poolId = url.searchParams.get('pool_id');
        const { data, error } = await db1.rpc('intake_dlq_read', { p_batch_size: 100 });
        if (error) return new Response(error.message, { status: 500 });

        const filtered = poolId
            ? (data ?? []).filter((m: { message: { pool_id?: string } }) => m.message?.pool_id === poolId)
            : (data ?? []);
        return new Response(JSON.stringify(filtered), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
        });
    }

    const path = url.pathname.split('/').pop();
    const body = await req.json();
    const { msg_ids }: { msg_ids: number[] } = body;

    // POST /admin-dlq/replay — move messages from DLQ back to intake_queue
    if (method === 'POST' && path === 'replay') {
        for (const msg_id of msg_ids) {
            // Read message from DLQ
            const { data: dlqMsgs } = await db1.rpc('intake_dlq_read', { p_batch_size: 1 });
            const msg = (dlqMsgs ?? []).find((m: { msg_id: number }) => m.msg_id === msg_id);
            if (!msg) continue;

            // Re-queue to intake_queue (reset state to 'queued')
            const payload = { ...msg.message, state: 'queued' };
            delete payload.original_msg_id;
            delete payload.final_read_ct;
            delete payload.routed_to_dlq_at;

            await db1.rpc('intake_queue_send', { p_payload: payload });
            await db1.rpc('intake_dlq_delete', { p_msg_ids: [msg_id] });
        }
        return new Response(JSON.stringify({ replayed: msg_ids.length }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
        });
    }

    // POST /admin-dlq/discard — permanently remove messages from DLQ
    if (method === 'POST' && path === 'discard') {
        await db1.rpc('intake_dlq_delete', { p_msg_ids: msg_ids });
        return new Response(JSON.stringify({ discarded: msg_ids.length }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
        });
    }

    return new Response('Not Found', { status: 404 });
});
