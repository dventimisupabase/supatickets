'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useCart } from '@/lib/cart-context'
import type { User } from '@supabase/supabase-js'

function CountdownBadge({ expiresAt }: { expiresAt: Date }) {
  const [remaining, setRemaining] = useState('')

  useEffect(() => {
    const tick = () => {
      const diff = expiresAt.getTime() - Date.now()
      if (diff <= 0) { setRemaining('0:00'); return }
      const mins = Math.floor(diff / 60000)
      const secs = Math.floor((diff % 60000) / 1000)
      setRemaining(`${mins}:${secs.toString().padStart(2, '0')}`)
    }
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [expiresAt])

  const diff = expiresAt.getTime() - Date.now()
  const urgent = diff < 120000

  return (
    <span className={`text-xs font-mono ${urgent ? 'text-red-400' : 'text-zinc-400'}`}>
      {remaining}
    </span>
  )
}

export default function Navbar() {
  const [user, setUser] = useState<User | null>(null)
  const supabase = createClient()
  const { items, soonestExpiry, shielded, setShielded } = useCart()

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
          <a href="/about/" className="text-sm text-zinc-400 hover:text-white">About</a>
        </div>

        <div className="flex items-center gap-4">
          <button
            onClick={() => setShielded(!shielded)}
            className="flex items-center gap-2 rounded-full border border-zinc-800 bg-zinc-900 px-3 py-1"
            title={shielded ? 'Using shielded path (DB1 → DB2)' : 'Using unshielded path (DB2 only)'}
          >
            <div className={`relative h-4 w-7 rounded-full transition-colors ${shielded ? 'bg-cyan-500' : 'bg-amber-500'}`}>
              <div className={`absolute top-0.5 h-3 w-3 rounded-full bg-white transition-transform ${shielded ? 'left-3.5' : 'left-0.5'}`} />
            </div>
            <span className={`text-xs font-medium ${shielded ? 'text-cyan-400' : 'text-amber-400'}`}>
              {shielded ? 'Shielded' : 'Unshielded'}
            </span>
          </button>

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
            <Link href="/auth/login" className="text-sm text-zinc-400 hover:text-white">Sign In</Link>
          )}
        </div>
      </div>
    </nav>
  )
}
