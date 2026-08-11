import Link from 'next/link'

export default async function ConfirmationPage({ searchParams }: { searchParams: Promise<{ order?: string }> }) {
  const { order } = await searchParams

  return (
    <div className="mx-auto max-w-md text-center">
      <div className="mb-6 text-6xl">&#10003;</div>
      <h1 className="mb-2 text-3xl font-bold">Purchase Confirmed!</h1>
      <p className="mb-2 text-zinc-400">Your tickets have been booked.</p>
      {order && <p className="mb-6 text-xs text-zinc-500">Order: {order}</p>}

      <div className="flex justify-center gap-4">
        <Link href="/account" className="rounded-lg bg-cyan-500 px-6 py-2 font-semibold text-black hover:bg-cyan-400">
          View Orders
        </Link>
        <Link href="/" className="rounded-lg border border-zinc-600 px-6 py-2 font-semibold text-zinc-300 hover:bg-zinc-800">
          Browse Events
        </Link>
      </div>
    </div>
  )
}
