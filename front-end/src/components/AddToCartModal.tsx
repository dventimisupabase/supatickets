'use client'

import { useRouter } from 'next/navigation'

export default function AddToCartModal({ onClose }: { onClose: () => void }) {
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
