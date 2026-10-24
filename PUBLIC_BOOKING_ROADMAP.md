# Public Booking — Selective Improvement Plan

Production baseline: 090a3dde8ca3ec38baa7b9b04eb851009de99875
Branch: feature/public-booking-selective-20261025
Scope: 8,12,13,14,18,31,33,34,41,42,45.

## Implemented in branch
- Correct sharing copy to say booking **request** pending confirmation rather than confirmed booking.
- Instrument booking_submit_attempt before the submit RPC, enabling attempted-to-submitted funnel analysis.

## Required before any production deployment
- 42: Implement server-side idempotency key with unique constraint and transactional booking request creation; test same-key retries, simultaneous requests, and distinct bookings. Never change live RPC until reviewed.
- 33: Link visit_id and booking request ID and confirmed booking to calculate confirmed-booking conversion, not just submitted requests.
- 34: Validate demand-interest lifecycle contacted_at / converted_at; group by venue, operating date, hour.
- 8: Source authentic venue photos with owner approval, compressed variants, alt text and per-venue display.
- 12: Verify share flow on iOS/Android, and never label unconfirmed request as confirmed.
- 13: Private post-play rating endpoint, verified booking ownership, RLS; owner-only reporting.
- 14: Existing local customer prefill; improve repeat-booking path without retaining sensitive details indefinitely.
- 18: Add verified venue SEO pages and structured data with real address/hours; avoid fabricated reviews.
- 31: Post-request sponsor coupons; redeemability/expiry and conversion tracking, no misleading confirmation.
- 41: Installable PWA with icons and offline shell; never cache availability or prices as authoritative.
- 45: Keyboard/focus/contrast/touch target and screen-reader QA.

## QA gates
- JS parse and browser console, iOS/Android, 320px, 360px, 390px.
- Public RPC RLS/security, no public customer/review access.
- Operating-day boundary 06:00 Cairo; midnight slots; duplicate and concurrent submissions.
- Funnel event deduplication and reconciliation to booking requests.
- Lighthouse performance/accessibility/SEO and PWA offline behavior.
- Preview-only sign-off before any production change.

## Important
The current production Supabase project is shared by staff and public booking. Do not execute DDL or mutate live data during preview development. Use isolated test fixtures and a separate test environment for database changes.
