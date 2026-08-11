import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import Navbar from '@/components/Navbar'
import { CartProvider } from '@/lib/cart-context'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'SupaTickets',
  description: 'SupaTickets — a ticket marketplace demo powered by Supabase',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.className} bg-zinc-950 text-zinc-100 antialiased`}>
        <CartProvider>
          <Navbar />
          <main className="mx-auto max-w-6xl px-4 py-8">
            {children}
          </main>
        </CartProvider>
      </body>
    </html>
  )
}
