// ==============================================================================
// SUPABASE INTAKE ENGINE: BRIDGE WORKER
// ==============================================================================
// This function is triggered by pg_cron/pg_net from DB1.
// It drains the 'intake_queue', calls external validation (Stripe), and commits to DB2.

import postgres from 'https://deno.land/x/postgresjs/mod.js';

// 1. Connection Setup (Using Environment Variables)
// We keep connection pools small because Edge Functions are ephemeral and can scale horizontally.
const sqlDB1 = postgres(Deno.env.get('DB1_CONNECTION_STRING')!, {
  max: 5,
  idle_timeout: 2,
});

const sqlDB2 = postgres(Deno.env.get('DB2_CONNECTION_STRING')!, {
  max: 5,
  idle_timeout: 2,
});

// Engine Configuration Parameters
const QUEUE_NAME = 'intake_queue';
const VISIBILITY_TIMEOUT = 45; // Seconds the message is hidden from other workers
const BATCH_SIZE = 100;        // Drains 100 tickets per invocation

// Expected Payload Structure from DB1
interface QueuePayload {
  pool_id: string;
  resource_id: string;
  user_id: string;
  state: 'queued' | 'validated' | 'committed';
}

Deno.serve(async (req) => {
  try {
    // ==============================================================================
    // PHASE 1: ACQUIRE (Read from DB1)
    // ==============================================================================
    // pgmq.read safely pops and locks messages. If this function crashes, 
    // the messages reappear on the queue in 45 seconds.
    const messages = await sqlDB1`
      SELECT * FROM pgmq.read(${QUEUE_NAME}, ${VISIBILITY_TIMEOUT}, ${BATCH_SIZE});
    `;

    if (messages.length === 0) {
      return new Response(JSON.stringify({ status: "idle", message: "Queue is empty" }), { status: 200 });
    }

    console.log(`[Bridge Worker] Pulled ${messages.length} messages from ${QUEUE_NAME}`);
    
    const successfulMessageIds: string[] = [];

    // ==============================================================================
    // PHASE 2: PROCESS & COMMIT (Iterate through the batch)
    // ==============================================================================
    for (const msg of messages) {
      const payload = msg.message as QueuePayload;
      
      try {
        // --- STEP A: VALIDATION (External Business Logic / Stripe) ---
        // If the state is already 'validated' (meaning a previous run crashed before DB2 commit),
        // we skip the webhook to prevent double-charging the user.
        if (payload.state === 'queued') {
          console.log(`[Validating] Payment for resource: ${payload.resource_id}`);
          
          /* AI AGENT INSTRUCTION: Inject actual HTTP POST to Validation Webhook here.
            Example:
            const webhookRes = await fetch(Deno.env.get('VALIDATION_WEBHOOK_URL'), {
              method: 'POST', body: JSON.stringify({ resource_id: payload.resource_id, ... })
            });
            if (!webhookRes.ok) throw new Error("Validation Failed");
          */

          // Update state in DB1's queue payload to prevent double-processing on retries
          // (Requires a custom pgmq update or handling via DLQ logic if complex)
          payload.state = 'validated'; 
        }

        // --- STEP B: COMMIT TO LEDGER (Write to DB2) ---
        console.log(`[Committing] Finalizing record to DB2 for resource: ${payload.resource_id}`);
        
        /* AI AGENT INSTRUCTION: Inject RPC call to DB2 here.
          The RPC on DB2 is responsible for unpacking the JSON and inserting into legacy tables.
        */
        await sqlDB2`
          SELECT finalize_transaction(${JSON.stringify(payload)}::jsonb);
        `;

        // If we reach this line, both validation and DB2 commit were successful.
        successfulMessageIds.push(msg.msg_id);

      } catch (error) {
        // We log the error but DO NOT add the msg_id to successfulMessageIds.
        // It remains hidden in pgmq and will automatically be retried in 45 seconds.
        console.error(`[Error] Failed processing message ${msg.msg_id}:`, error);
      }
    }

    // ==============================================================================
    // PHASE 3: ACKNOWLEDGE (Delete from DB1)
    // ==============================================================================
    if (successfulMessageIds.length > 0) {
      console.log(`[Acknowledge] Deleting ${successfulMessageIds.length} processed messages.`);
      
      await sqlDB1`
        SELECT pgmq.delete(${QUEUE_NAME}, ${successfulMessageIds});
      `;
    }

    return new Response(
      JSON.stringify({ 
        status: "success", 
        processed: successfulMessageIds.length, 
        total: messages.length 
      }), 
      { status: 200, headers: { "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("[Fatal Error] Worker execution failed:", err);
    return new Response("Internal Server Error", { status: 500 });
  } finally {
    // Always release database connections when the Edge Function finishes
    await sqlDB1.end();
    await sqlDB2.end();
  }
});
