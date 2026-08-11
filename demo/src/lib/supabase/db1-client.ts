import { createClient } from '@supabase/supabase-js'

export function createDb1Client() {
  return createClient(
    process.env.NEXT_PUBLIC_DB1_URL!,
    process.env.NEXT_PUBLIC_DB1_ANON_KEY!
  )
}
