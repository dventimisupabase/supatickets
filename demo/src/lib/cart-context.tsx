'use client'

import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from 'react'
import { createClient } from '@/lib/supabase/client'
import { createDb1Client } from '@/lib/supabase/db1-client'
import type { CartItem } from '@/types/database'

interface CartContextType {
  items: CartItem[]
  loading: boolean
  soonestExpiry: Date | null
  shielded: boolean
  setShielded: (v: boolean) => void
  refresh: () => Promise<void>
  addToCart: (eventId: string, count: number) => Promise<{ success: boolean; error?: string }>
  removeFromCart: (eventId: string) => Promise<void>
  checkout: () => Promise<{ orderId: string | null; error?: string }>
}

const CartContext = createContext<CartContextType | null>(null)

export function CartProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<CartItem[]>([])
  const [loading, setLoading] = useState(true)
  const [shielded, setShielded] = useState(true)
  const supabase = createClient()
  const db1 = createDb1Client()

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
    refresh()

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
        const { data: { user } } = await supabase.auth.getUser()
        for (const item of expired) {
          if (shielded && user) {
            try {
              await db1.rpc('unclaim_slot', { p_pool_id: item.event_id, p_user_id: user.id })
            } catch {
              // DB1 unreachable — orphaned slots reaped by cron
            }
          }
          await supabase.rpc('unclaim_tickets', { p_event_id: item.event_id })
        }
        refresh()
      }
    }, 1000)

    return () => clearInterval(interval)
  }, [items, supabase, db1, shielded, refresh])

  const soonestExpiry = items.length > 0
    ? new Date(Math.min(...items.map(i => new Date(i.expires_at).getTime())))
    : null

  const addToCart = async (eventId: string, count: number) => {
    // Get user from DB2 auth
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { success: false, error: 'Not authenticated' }

    if (shielded) {
      // Step 1: Claim slots on DB1 (concurrency gatekeeper)
      const claimedSlots: string[] = []
      for (let i = 0; i < count; i++) {
        const { data, error } = await db1.rpc('claim_resource_and_queue', {
          p_pool_id: eventId,
          p_user_id: user.id,
        })
        if (error) {
          if (claimedSlots.length > 0) {
            await db1.rpc('unclaim_slot', { p_pool_id: eventId, p_user_id: user.id })
          }
          return { success: false, error: error.message }
        }
        if (!data) {
          if (claimedSlots.length > 0) {
            await db1.rpc('unclaim_slot', { p_pool_id: eventId, p_user_id: user.id })
          }
          return { success: false, error: 'Not enough tickets available' }
        }
        claimedSlots.push(data)
      }
    }

    // Step 2: Record reservation on DB2 (bookkeeping)
    const { data, error } = await supabase.rpc('claim_tickets', {
      p_event_id: eventId,
      p_count: count,
    })

    if (error || !data) {
      if (shielded) {
        await db1.rpc('unclaim_slot', { p_pool_id: eventId, p_user_id: user.id })
      }
      return { success: false, error: error?.message ?? 'Failed to reserve tickets' }
    }

    await refresh()
    return { success: true }
  }

  const removeFromCart = async (eventId: string) => {
    if (shielded) {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        try {
          await db1.rpc('unclaim_slot', { p_pool_id: eventId, p_user_id: user.id })
        } catch {
          // DB1 unreachable — orphaned slots reaped by cron
        }
      }
    }
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
    <CartContext.Provider value={{ items, loading, soonestExpiry, shielded, setShielded, refresh, addToCart, removeFromCart, checkout }}>
      {children}
    </CartContext.Provider>
  )
}

export function useCart() {
  const ctx = useContext(CartContext)
  if (!ctx) throw new Error('useCart must be used within CartProvider')
  return ctx
}
