import Link from 'next/link'
import type { Event } from '@/types/database'

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

export default function EventCard({ event, available }: { event: Event; available: number }) {
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
