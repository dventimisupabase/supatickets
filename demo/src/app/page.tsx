import { createClient } from '@/lib/supabase/server'
import EventCard from '@/components/EventCard'
import type { Event } from '@/types/database'

export const revalidate = 30

export default async function HomePage() {
  const supabase = await createClient()

  const { data: events } = await supabase
    .from('events')
    .select('*')
    .order('date')

  const availability: Record<string, number> = {}
  if (events) {
    await Promise.all(
      events.map(async (event: Event) => {
        const { data } = await supabase.rpc('get_event_availability', { p_event_id: event.id })
        availability[event.id] = data ?? 0
      })
    )
  }

  return (
    <div>
      <h1 className="mb-2 text-3xl font-bold">Upcoming Events</h1>
      <p className="mb-8 text-zinc-400">Find and book tickets for live events</p>

      <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        {events?.map((event: Event) => (
          <EventCard key={event.id} event={event} available={availability[event.id] ?? 0} />
        ))}
      </div>

      {(!events || events.length === 0) && (
        <p className="text-center text-zinc-500">No events available.</p>
      )}
    </div>
  )
}
