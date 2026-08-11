'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useCart } from '@/lib/cart-context'
import { createClient } from '@/lib/supabase/client'
import AddToCartModal from './AddToCartModal'

export default function TicketSelector({ eventId, available, price }: {
  eventId: string
  available: number
  price: number
}) {
  const [count, setCount] = useState(1)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showModal, setShowModal] = useState(false)
  const { addToCart } = useCart()
  const router = useRouter()
  const supabase = createClient()

  const maxTickets = Math.min(available, 10)

  const handleAddToCart = async () => {
    setLoading(true)
    setError(null)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      router.push('/auth/login')
      return
    }

    const result = await addToCart(eventId, count)
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
          <label className="text-sm text-zinc-400">Number of tickets</label>
          <select
            value={count}
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
          <span className="text-2xl font-bold text-white">${(price * count).toFixed(2)}</span>
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
