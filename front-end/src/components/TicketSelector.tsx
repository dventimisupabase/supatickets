'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useCart } from '@/lib/cart-context'
import { createClient } from '@/lib/supabase/client'
import AddToCartModal from './AddToCartModal'

export default function TicketSelector({ eventId, available: initialAvailable, price }: {
  eventId: string
  available: number
  price: number
}) {
  const [available, setAvailable] = useState(initialAvailable)
  const [count, setCount] = useState(1)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showModal, setShowModal] = useState(false)
  const { addToCart } = useCart()
  const router = useRouter()
  const supabase = createClient()

  // Live "tickets left": Realtime pushes a change, we re-fetch the count.
  useEffect(() => {
    const channel = supabase
      .channel(`event-tickets-${eventId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'event_tickets', filter: `event_id=eq.${eventId}` },
        async () => {
          const { data } = await supabase.rpc('get_event_availability', { p_event_id: eventId })
          setAvailable(data ?? 0)
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [eventId, supabase])

  const maxTickets = Math.min(available, 10)
  // Availability can drop below the previously selected count while live.
  const effectiveCount = Math.min(count, Math.max(maxTickets, 1))

  const handleAddToCart = async () => {
    setLoading(true)
    setError(null)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      router.push('/auth/login')
      return
    }

    const result = await addToCart(eventId, effectiveCount)
    setLoading(false)

    if (result.success) {
      setShowModal(true)
    } else {
      setError(result.error ?? 'Failed to add tickets')
    }
  }

  if (available === 0) {
    return <div className="rounded-lg bg-zinc-800 p-6 text-center text-zinc-400">Sold Out</div>
  }

  return (
    <>
      <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-6">
        <div className="mb-4 flex items-center justify-between">
          <span className="text-sm text-zinc-400">Available</span>
          <span className="font-mono text-lg text-cyan-400">{available.toLocaleString()}</span>
        </div>

        <div className="mb-4 flex items-center justify-between">
          <label className="text-sm text-zinc-400">Number of tickets</label>
          <select
            value={effectiveCount}
            onChange={(e) => setCount(Number(e.target.value))}
            className="rounded bg-zinc-800 px-3 py-1 text-white"
          >
            {Array.from({ length: maxTickets }, (_, i) => i + 1).map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
        </div>

        <div className="mb-4 flex items-center justify-between border-t border-zinc-800 pt-4">
          <span className="text-zinc-400">Total</span>
          <span className="text-2xl font-bold text-white">${(price * effectiveCount).toFixed(2)}</span>
        </div>

        {error && <p className="mb-4 text-sm text-red-400">{error}</p>}

        <button
          onClick={handleAddToCart}
          disabled={loading}
          className="w-full rounded-lg bg-cyan-500 py-3 font-semibold text-black transition hover:bg-cyan-400 disabled:opacity-50"
        >
          {loading ? 'Reserving...' : 'Add to Cart'}
        </button>

        <p className="mt-2 text-center text-xs text-zinc-500">
          Tickets are held for 20 minutes
        </p>
      </div>

      {showModal && <AddToCartModal onClose={() => setShowModal(false)} />}
    </>
  )
}
