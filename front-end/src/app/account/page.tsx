import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import type { Order, OrderItem } from '@/types/database'

export default async function AccountPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/auth/login')

  const { data: orders } = await supabase
    .from('orders')
    .select('*, order_items:order_items(*, event:events(name, venue, date))')
    .order('created_at', { ascending: false })

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-2 text-3xl font-bold">Account</h1>
      <p className="mb-8 text-zinc-400">{user.email}</p>

      <h2 className="mb-4 text-xl font-semibold">Purchase History</h2>

      {(!orders || orders.length === 0) ? (
        <p className="text-zinc-500">No purchases yet.</p>
      ) : (
        <div className="space-y-4">
          {orders.map((order: Order & { order_items: (OrderItem & { event: { name: string; venue: string; date: string } })[] }) => (
            <div key={order.id} className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-sm text-zinc-400">
                  {new Date(order.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                </span>
                <span className="font-bold text-white">${order.total_amount.toFixed(2)}</span>
              </div>

              {order.order_items.map((item) => (
                <div key={item.id} className="flex justify-between text-sm">
                  <span className="text-zinc-300">
                    <Link href={`/event/${item.event_id}`} className="text-cyan-400 hover:underline">
                      {item.event?.name}
                    </Link>
                    {' '}— {item.ticket_count} ticket{item.ticket_count > 1 ? 's' : ''}
                  </span>
                  <span className="text-zinc-400">${(item.unit_price * item.ticket_count).toFixed(2)}</span>
                </div>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
