'use client'

import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import type { User } from '@supabase/supabase-js'
import { createClient, type CartItem, type Event } from '@/lib/supabase'

// === Cart context ===
// Shared client-side cart state, backed by the cart_items table and the
// claim_tickets / unclaim_tickets / checkout_cart RPCs.

interface CartContextType {
  items: CartItem[]
  loading: boolean
  soonestExpiry: Date | null
  refresh: () => Promise<void>
  addToCart: (eventId: string, count: number) => Promise<{ success: boolean; error?: string }>
  removeFromCart: (eventId: string) => Promise<void>
  checkout: () => Promise<{ orderId: string | null; error?: string }>
}

const CartContext = createContext<CartContextType | null>(null)

export function CartProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<CartItem[]>([])
  const [loading, setLoading] = useState(true)
  const supabase = createClient()

  const refresh = useCallback(async () => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      setItems([])
      setLoading(false)
      return
    }

    const { data } = await supabase
      .from('cart_items')
      .select('*, event:events(*)')
      .order('created_at')

    setItems(data ?? [])
    setLoading(false)
  }, [supabase])

  useEffect(() => {
    void (async () => {
      await refresh()
    })()

    const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
      refresh()
    })

    return () => subscription.unsubscribe()
  }, [supabase, refresh])

  // Remove expired items client-side
  useEffect(() => {
    const interval = setInterval(async () => {
      const now = new Date()
      const expired = items.filter(item => new Date(item.expires_at) <= now)
      if (expired.length > 0) {
        for (const item of expired) {
          await supabase.rpc('unclaim_tickets', { p_event_id: item.event_id })
        }
        refresh()
      }
    }, 1000)

    return () => clearInterval(interval)
  }, [items, supabase, refresh])

  const soonestExpiry = items.length > 0
    ? new Date(Math.min(...items.map(i => new Date(i.expires_at).getTime())))
    : null

  const addToCart = async (eventId: string, count: number) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { success: false, error: 'Not authenticated' }

    const { data, error } = await supabase.rpc('claim_tickets', {
      p_event_id: eventId,
      p_count: count,
    })

    if (error || !data) {
      return { success: false, error: error?.message ?? 'Not enough tickets available' }
    }

    await refresh()
    return { success: true }
  }

  const removeFromCart = async (eventId: string) => {
    await supabase.rpc('unclaim_tickets', { p_event_id: eventId })
    await refresh()
  }

  const checkout = async () => {
    const { data, error } = await supabase.rpc('checkout_cart')

    if (error) return { orderId: null, error: error.message }

    await refresh()
    return { orderId: data }
  }

  return (
    <CartContext.Provider value={{ items, loading, soonestExpiry, refresh, addToCart, removeFromCart, checkout }}>
      {children}
    </CartContext.Provider>
  )
}

export function useCart() {
  const ctx = useContext(CartContext)
  if (!ctx) throw new Error('useCart must be used within CartProvider')
  return ctx
}

// === AddToCartModal ===

function AddToCartModal({ onClose }: { onClose: () => void }) {
  const router = useRouter()

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className="w-full max-w-sm rounded-xl border border-zinc-700 bg-zinc-900 p-6">
        <h2 className="mb-2 text-xl font-bold text-white">Added to Cart!</h2>
        <p className="mb-6 text-sm text-zinc-400">
          Your tickets are reserved for 20 minutes.
        </p>

        <div className="flex gap-3">
          <button
            onClick={() => router.push('/cart')}
            className="flex-1 rounded-lg bg-cyan-500 py-2 font-semibold text-black hover:bg-cyan-400"
          >
            Checkout
          </button>
          <button
            onClick={() => { onClose(); router.push('/') }}
            className="flex-1 rounded-lg border border-zinc-600 py-2 font-semibold text-zinc-300 hover:bg-zinc-800"
          >
            Continue Shopping
          </button>
        </div>
      </div>
    </div>
  )
}

// === Navbar ===

function CountdownBadge({ expiresAt }: { expiresAt: Date }) {
  const [remaining, setRemaining] = useState('')
  const [urgent, setUrgent] = useState(false)

  useEffect(() => {
    const tick = () => {
      const diff = expiresAt.getTime() - Date.now()
      setUrgent(diff < 120000)
      if (diff <= 0) { setRemaining('0:00'); return }
      const mins = Math.floor(diff / 60000)
      const secs = Math.floor((diff % 60000) / 1000)
      setRemaining(`${mins}:${secs.toString().padStart(2, '0')}`)
    }
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [expiresAt])

  return (
    <span className={`text-xs font-mono ${urgent ? 'text-red-400' : 'text-zinc-400'}`}>
      {remaining}
    </span>
  )
}

export function Navbar() {
  const [user, setUser] = useState<User | null>(null)
  const supabase = createClient()
  const { items, soonestExpiry } = useCart()

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user))
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_, session) => {
      setUser(session?.user ?? null)
    })
    return () => subscription.unsubscribe()
  }, [supabase])

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    window.location.href = '/'
  }

  return (
    <nav className="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-950/90 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
        <div className="flex items-center gap-6">
          <Link href="/" className="text-lg font-bold text-white">SupaTickets</Link>
          <Link href="/" className="text-sm text-zinc-400 hover:text-white">Home</Link>
        </div>

        <div className="flex items-center gap-4">
          {user ? (
            <>
              <Link href="/cart" className="relative flex items-center gap-1 text-sm text-zinc-400 hover:text-white">
                Cart
                {items.length > 0 && (
                  <span className="flex items-center gap-1">
                    <span className="rounded-full bg-cyan-500 px-1.5 py-0.5 text-xs font-bold text-black">
                      {items.length}
                    </span>
                    {soonestExpiry && <CountdownBadge expiresAt={soonestExpiry} />}
                  </span>
                )}
              </Link>
              <Link href="/account" className="text-sm text-zinc-400 hover:text-white">Account</Link>
              <button onClick={handleSignOut} className="text-sm text-zinc-400 hover:text-white">
                Sign Out
              </button>
            </>
          ) : (
            <Link href="/login" className="text-sm text-zinc-400 hover:text-white">Sign In</Link>
          )}
        </div>
      </div>
    </nav>
  )
}

// === EventCard ===

function AvailabilityBadge({ available, total }: { available: number; total: number }) {
  const pct = available / total
  const color = pct > 0.5 ? 'bg-emerald-500' : pct > 0.1 ? 'bg-amber-500' : pct > 0 ? 'bg-red-500' : 'bg-zinc-600'
  const label = available === 0 ? 'Sold Out' : `${available.toLocaleString()} left`

  return (
    <span className={`rounded-full px-2 py-0.5 text-xs font-semibold text-black ${color}`}>
      {label}
    </span>
  )
}

export function EventCard({ event, available }: { event: Event; available: number }) {
  const date = new Date(event.date)

  return (
    <Link href={`/event/${event.id}`} className="group block overflow-hidden rounded-xl border border-zinc-800 bg-zinc-900 transition hover:border-zinc-600">
      <div className="relative h-48 overflow-hidden bg-gradient-to-br from-zinc-800 to-zinc-900">
        {event.image_url && (
          <img src={event.image_url} alt={event.name} className="h-full w-full object-cover transition group-hover:scale-105" />
        )}
        <div className="absolute right-2 top-2">
          <AvailabilityBadge available={available} total={event.total_tickets} />
        </div>
      </div>
      <div className="p-4">
        <h3 className="font-semibold text-white">{event.name}</h3>
        <p className="mt-1 text-sm text-zinc-400">
          {date.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })}
        </p>
        <p className="text-sm text-zinc-500">{event.venue} — {event.location}</p>
        <p className="mt-2 text-lg font-bold text-cyan-400">${event.ticket_price.toFixed(2)}</p>
      </div>
    </Link>
  )
}

// === TicketSelector ===

export function TicketSelector({ eventId, available: initialAvailable, price }: {
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
      router.push('/login')
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

// === CartItemRow ===

export function CartItemRow({ item }: { item: CartItem }) {
  const { removeFromCart } = useCart()
  const [remaining, setRemaining] = useState('')
  const [expired, setExpired] = useState(false)
  const [urgent, setUrgent] = useState(false)
  const [removing, setRemoving] = useState(false)

  useEffect(() => {
    const tick = () => {
      const diff = new Date(item.expires_at).getTime() - Date.now()
      setExpired(diff <= 0)
      setUrgent(diff < 120000)
      if (diff <= 0) { setRemaining('Expired'); return }
      const mins = Math.floor(diff / 60000)
      const secs = Math.floor((diff % 60000) / 1000)
      setRemaining(`${mins}:${secs.toString().padStart(2, '0')}`)
    }
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [item.expires_at])

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
