'use client'

import { useEffect, useState } from 'react'
import { useCart } from '@/lib/cart-context'

export default function CartItemRow({ item }: { item: { event_id: string; ticket_count: number; expires_at: string; event?: { name: string; ticket_price: number; venue: string } } }) {
  const { removeFromCart } = useCart()
  const [remaining, setRemaining] = useState('')
  const [removing, setRemoving] = useState(false)

  useEffect(() => {
    const tick = () => {
      const diff = new Date(item.expires_at).getTime() - Date.now()
      if (diff <= 0) { setRemaining('Expired'); return }
      const mins = Math.floor(diff / 60000)
      const secs = Math.floor((diff % 60000) / 1000)
      setRemaining(`${mins}:${secs.toString().padStart(2, '0')}`)
    }
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [item.expires_at])

  const expired = new Date(item.expires_at).getTime() <= Date.now()
  const diff = new Date(item.expires_at).getTime() - Date.now()
  const urgent = diff < 120000

  const handleRemove = async () => {
    setRemoving(true)
    await removeFromCart(item.event_id)
  }

  if (expired) return null

  return (
    <div className="flex items-center justify-between rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex-1">
        <h3 className="font-semibold text-white">{item.event?.name ?? 'Unknown Event'}</h3>
        <p className="text-sm text-zinc-400">
          {item.ticket_count} ticket{item.ticket_count > 1 ? 's' : ''} × ${item.event?.ticket_price.toFixed(2)}
        </p>
        <p className="text-xs text-zinc-500">{item.event?.venue}</p>
      </div>

      <div className="flex items-center gap-4">
        <div className="text-right">
          <p className="font-bold text-white">
            ${((item.event?.ticket_price ?? 0) * item.ticket_count).toFixed(2)}
          </p>
          <p className={`text-xs font-mono ${urgent ? 'text-red-400' : 'text-zinc-400'}`}>
            {remaining}
          </p>
        </div>

        <button
          onClick={handleRemove}
          disabled={removing}
          className="rounded px-3 py-1 text-sm text-zinc-400 hover:bg-zinc-800 hover:text-white"
        >
          {removing ? '...' : 'Remove'}
        </button>
      </div>
    </div>
  )
}
