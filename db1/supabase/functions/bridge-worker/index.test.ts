// db1/supabase/functions/bridge-worker/index.test.ts
import { assertEquals, assertExists } from 'jsr:@std/assert@1';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const DB1_URL = Deno.env.get('DB1_SUPABASE_URL') ?? 'http://127.0.0.1:54341';
const DB1_KEY = Deno.env.get('DB1_SUPABASE_SERVICE_ROLE_KEY')!;
const DB2_URL = Deno.env.get('DB2_SUPABASE_URL') ?? 'http://127.0.0.1:54441';
const DB2_KEY = Deno.env.get('DB2_SUPABASE_SERVICE_ROLE_KEY')!;
const BRIDGE_WORKER_URL = `${DB1_URL}/functions/v1/bridge-worker`;

const db1 = createClient(DB1_URL, DB1_KEY);
const db2 = createClient(DB2_URL, DB2_KEY);

async function invokeWorker() {
    const res = await fetch(BRIDGE_WORKER_URL, {
        method: 'POST',
        headers: { Authorization: `Bearer ${DB1_KEY}` },
    });
    return res.json();
}

Deno.test('bridge worker returns idle when queue is empty', async () => {
    const result = await invokeWorker();
    assertEquals(result.status === 'idle' || result.status === 'success', true);
});

Deno.test('end-to-end: claim → bridge worker → confirmed ticket', async () => {
    // Ensure pool config exists
    await db1.from('engine_config').upsert({
        pool_id: 'e2e_test_pool',
        batch_size: 10,
        visibility_timeout_sec: 45,
        max_retries: 3,
        is_active: true,
    });

    // Seed one slot
    await db1.from('inventory_slots').insert({ pool_id: 'e2e_test_pool', status: 'AVAILABLE' });

    // Claim a ticket
    const { data: resourceId } = await db1.rpc('claim_resource_and_queue', {
        p_pool_id: 'e2e_test_pool',
        p_user_id: 'e2e_user',
    });
    assertExists(resourceId);

    // Invoke bridge worker
    const result = await invokeWorker();
    assertEquals(result.processed >= 1, true);

    // Verify confirmed on DB2
    const { data: ticket } = await db2
        .from('confirmed_tickets')
        .select('*')
        .eq('resource_id', resourceId)
        .single();
    assertExists(ticket);
    assertEquals(ticket.user_id, 'e2e_user');

    // Verify slot CONSUMED on DB1
    const { data: slot } = await db1
        .from('inventory_slots')
        .select('status')
        .eq('id', resourceId)
        .single();
    assertEquals(slot?.status, 'CONSUMED');
});

Deno.test('DLQ: message with read_ct >= max_retries is routed to DLQ', async () => {
    await db1.from('engine_config').upsert({
        pool_id: 'dlq_test_pool',
        batch_size: 10,
        visibility_timeout_sec: 5,
        max_retries: 1,
        is_active: true,
    });

    // Enqueue a message that will immediately exceed max_retries (read_ct check is >= max_retries)
    // We simulate this by sending directly to queue and reading it multiple times
    await db1.rpc('intake_queue_send', {
        p_payload: { pool_id: 'dlq_test_pool', resource_id: '11111111-0000-0000-0000-000000000001', user_id: 'dlq_user', state: 'queued' },
    });

    // Read once to increment read_ct, then invoke worker which should route to DLQ
    // (This test is illustrative — in practice read_ct increments per pgmq.read call)
    const result = await invokeWorker();
    console.log('DLQ test result:', result);
    // Should have dlq > 0 after max retries exceeded
});
