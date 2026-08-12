import { createServerComponentClient, type Event } from '@/lib/supabase'
import { EventCard } from '@/components'

export const revalidate = 30

export default async function HomePage() {
  const supabase = await createServerComponentClient()

  const { data: events, error: eventsError } = await supabase
    .from('events')
    .select('*')
    .order('date')
  if (eventsError) console.error('Failed to load events:', eventsError)

  const { data: availabilityRows, error: availabilityError } = await supabase.rpc('get_events_availability')
  if (availabilityError) console.error('Failed to load ticket availability:', availabilityError)
  const availability: Record<string, number> = {}
  availabilityRows?.forEach((row: { event_id: string; available: number }) => {
    availability[row.event_id] = row.available
  })

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
