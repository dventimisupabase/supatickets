import { createClient } from '@/lib/supabase/server'
import { notFound } from 'next/navigation'
import TicketSelector from '@/components/TicketSelector'

export const revalidate = 10

export default async function EventPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const supabase = await createClient()

  const { data: event } = await supabase
    .from('events')
    .select('*')
    .eq('id', id)
    .single()

  if (!event) notFound()

  const { data: available } = await supabase.rpc('get_event_availability', { p_event_id: id })
  const date = new Date(event.date)

  return (
    <div className="grid gap-8 lg:grid-cols-3">
      <div className="lg:col-span-2">
        <div className="mb-6 h-64 overflow-hidden rounded-xl bg-gradient-to-br from-zinc-800 to-zinc-900 lg:h-80">
          {event.image_url && (
            <img src={event.image_url} alt={event.name} className="h-full w-full object-cover" />
          )}
        </div>

        <h1 className="mb-2 text-3xl font-bold">{event.name}</h1>

        <div className="mb-4 flex flex-wrap gap-4 text-sm text-zinc-400">
          <span>{date.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}</span>
          <span>{date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}</span>
        </div>

        <div className="mb-6 flex gap-4 text-sm">
          <span className="text-zinc-400">{event.venue}</span>
          <span className="text-zinc-500">{event.location}</span>
        </div>

        {event.description && (
          <p className="text-zinc-300 leading-relaxed">{event.description}</p>
        )}
      </div>

      <div>
        <TicketSelector eventId={id} available={available ?? 0} price={event.ticket_price} />
      </div>
    </div>
  )
}
