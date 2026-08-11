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
