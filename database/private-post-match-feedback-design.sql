-- DESIGN ONLY. DO NOT APPLY TO LIVE SUPABASE WITHOUT APPROVAL.
-- Private, post-match feedback tied to a confirmed real booking.
-- The public website must never SELECT feedback or accept an arbitrary booking ID as proof.
create table if not exists public.pitch_match_feedback (
  id uuid primary key default gen_random_uuid(),
  booking_id text not null references public.bookings(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text check (char_length(comment) <= 1000),
  created_at timestamptz not null default now(),
  unique (booking_id)
);
alter table public.pitch_match_feedback enable row level security;
revoke all on public.pitch_match_feedback from anon, authenticated;
-- No browser-facing direct INSERT/SELECT policy.
-- Implement a server-side RPC only after verifying booking completion, authenticated
-- one-time review token issuance, token hash storage, expiry, and replay prevention.
-- Admin-only reading should use the existing server-verified admin role mechanism.
-- Do not expose customer phone or private comments on the public website.
