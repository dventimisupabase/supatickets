'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useCart } from '@/lib/cart-context'
import CartItemRow from '@/components/CartItemRow'

export default function CartPage() {
  const { items, loading, checkout } = useCart()
  const [checkingOut, setCheckingOut] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const router = useRouter()

  const activeItems = items.filter(i => new Date(i.expires_at).getTime() > Date.now())
  const total = activeItems.reduce((sum, item) => {
    return sum + (item.event?.ticket_price ?? 0) * item.ticket_count
  }, 0)

  const handleCheckout = async () => {
    setCheckingOut(true)
    setError(null)
    const result = await checkout()
    setCheckingOut(false)

    if (result.orderId) {
      router.push(`/checkout/confirmation?order=${result.orderId}`)
    } else {
      setError(result.error ?? 'Checkout failed')
    }
  }

  if (loading) {
    return <p className="text-zinc-400">Loading cart...</p>
  }

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-6 text-3xl font-bold">Your Cart</h1>

      {activeItems.length === 0 ? (
        <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-8 text-center">
          <p className="text-zinc-400">Your cart is empty.</p>
          <a href="/" className="mt-4 inline-block text-cyan-400 hover:underline">Browse events</a>
        </div>
      ) : (
        <>
          <div className="mb-6 space-y-3">
            {activeItems.map(item => (
              <CartItemRow key={item.id} item={item} />
            ))}
          </div>

          <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-6">
            <div className="mb-4 flex items-center justify-between">
              <span className="text-lg text-zinc-400">Total</span>
              <span className="text-2xl font-bold text-white">${total.toFixed(2)}</span>
            </div>

            {error && <p className="mb-4 text-sm text-red-400">{error}</p>}

            <button
              onClick={handleCheckout}
              disabled={checkingOut}
              className="w-full rounded-lg bg-cyan-500 py-3 font-semibold text-black transition hover:bg-cyan-400 disabled:opacity-50"
            >
              {checkingOut ? 'Processing...' : 'Complete Purchase'}
            </button>

            <p className="mt-2 text-center text-xs text-zinc-500">
              Demo mode — no payment required
            </p>
          </div>
        </>
      )}
    </div>
  )
}
