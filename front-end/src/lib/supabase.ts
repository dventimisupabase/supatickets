import { createBrowserClient, createServerClient as createSupabaseServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

// === Types ===
// Mirrors the tables in back-end/01-schema.sql.

export interface Event {
  id: string
  name: string
  description: string | null
  date: string
  venue: string
  location: string
  image_url: string | null
  ticket_price: number
  total_tickets: number
  created_at: string
}

export interface CartItem {
  id: string
  user_id: string
  event_id: string
  ticket_count: number
  expires_at: string
  created_at: string
  event?: Event
}

export interface Order {
  id: string
  user_id: string
  total_amount: number
  created_at: string
}

export interface OrderItem {
  id: string
  order_id: string
  event_id: string
  ticket_count: number
  unit_price: number
  event?: Event
}

// Supabase's dashboard shows the REST endpoint (with /rest/v1 appended) in
// more places than it shows the bare project URL, so that's what people
// paste. supabase-js appends /rest/v1 itself, so a URL that already has it
// produces a doubled path and a silent PGRST125 on every request.
function supabaseUrl() {
  return process.env.NEXT_PUBLIC_SUPABASE_URL!.trim().replace(/\/rest\/v1\/?$/, '')
}

// === Browser client ===
// Use in Client Components ('use client').

export function createClient() {
  return createBrowserClient(
    supabaseUrl(),
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}

// === Server Component client ===
// Use in Server Components. Can read cookies but not write them.

export async function createServerComponentClient() {
  // Deferred import: next/headers can only be pulled into a Server Component
  // bundle, never a Client Component or Edge Middleware bundle. A static
  // top-level import here would poison every consumer of this file.
  const { cookies } = await import('next/headers')
  const cookieStore = await cookies()

  return createSupabaseServerClient(
    supabaseUrl(),
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
            // Server Component — can't set cookies, ignore
          }
        },
      },
    }
  )
}

// === Middleware ===
// Refreshes the auth session cookie on every request.

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createSupabaseServerClient(
    supabaseUrl(),
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  await supabase.auth.getUser()

  return supabaseResponse
}
