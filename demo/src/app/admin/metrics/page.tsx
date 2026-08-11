'use client'

import { useEffect, useState } from 'react'
import { createDb1Client } from '@/lib/supabase/db1-client'
import Link from 'next/link'

interface PoolMetrics {
  pool_id: string
  captured_at: string
  available_slots: number
  reserved_slots: number
  consumed_slots: number
  queue_depth: number
  dlq_depth: number
}

export default function MetricsPage() {
  const [metrics, setMetrics] = useState<PoolMetrics[]>([])
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const db1 = createDb1Client()

    const fetchMetrics = async () => {
      const { data, error: rpcError } = await db1.rpc('get_latest_metrics')
      if (rpcError) {
        setError(rpcError.message)
      } else {
        setMetrics(data ?? [])
        setError(null)
      }
      setLastRefresh(new Date())
    }

    fetchMetrics()
    const interval = setInterval(fetchMetrics, 10_000)
    return () => clearInterval(interval)
  }, [])

  const totalSlots = (m: PoolMetrics) =>
    m.available_slots + m.reserved_slots + m.consumed_slots

  return (
    <div className="mx-auto max-w-4xl">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">DB1 Engine Metrics</h1>
          <p className="text-sm text-zinc-400">
            Pool health &middot; refreshes every 10s
          </p>
        </div>
        <Link href="/" className="text-sm text-cyan-400 hover:underline">
          &larr; Back to events
        </Link>
      </div>

      {error && (
        <div className="mb-4 rounded-lg border border-red-800 bg-red-900/30 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      {metrics.length === 0 && !error ? (
        <p className="text-zinc-500">Loading metrics...</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-zinc-800">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-zinc-800 bg-zinc-900 text-zinc-400">
              <tr>
                <th className="px-4 py-3">Pool</th>
                <th className="px-4 py-3 text-right">Available</th>
                <th className="px-4 py-3 text-right">Reserved</th>
                <th className="px-4 py-3 text-right">Consumed</th>
                <th className="px-4 py-3 text-right">Total</th>
                <th className="px-4 py-3 text-right">Queue</th>
                <th className="px-4 py-3 text-right">DLQ</th>
                <th className="px-4 py-3 text-right">Snapshot</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {metrics.map((m) => (
                <tr key={m.pool_id} className="hover:bg-zinc-900/50">
                  <td className="px-4 py-3 font-mono text-xs">{m.pool_id}</td>
                  <td className="px-4 py-3 text-right text-green-400">
                    {m.available_slots.toLocaleString()}
                  </td>
                  <td className="px-4 py-3 text-right text-yellow-400">
                    {m.reserved_slots.toLocaleString()}
                  </td>
                  <td className="px-4 py-3 text-right text-cyan-400">
                    {m.consumed_slots.toLocaleString()}
                  </td>
                  <td className="px-4 py-3 text-right text-zinc-300">
                    {totalSlots(m).toLocaleString()}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <span className={m.queue_depth > 0 ? 'text-orange-400' : 'text-zinc-500'}>
                      {m.queue_depth.toLocaleString()}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <span className={m.dlq_depth > 0 ? 'text-red-400' : 'text-zinc-500'}>
                      {m.dlq_depth.toLocaleString()}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right text-xs text-zinc-500">
                    {new Date(m.captured_at).toLocaleTimeString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {lastRefresh && (
        <p className="mt-3 text-right text-xs text-zinc-600">
          Last refreshed: {lastRefresh.toLocaleTimeString()}
        </p>
      )}
    </div>
  )
}
