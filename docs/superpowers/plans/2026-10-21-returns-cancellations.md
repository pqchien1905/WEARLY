# Customer returns and authorized cancellation

> Execute inline using executing-plans, TDD and one independent review.

**Goal:** Persist customer return requests and physical receipts, with exact
discounted refund entitlement and authorized pre-dispatch cancellation.
**Architecture:** NestJS serializable order-locked commands, immutable return item
snapshots, versioned admin decisions; Flutter customer/admin panels. Actual money
refund execution follows in the next payment milestone.
**Spec:** `docs/superpowers/specs/2026-10-21-local-completion-design.md`.
**BASE:** 6392f7d.

## Rules and decisions

- Local default:7 days from an explicitly recorded DELIVERED OrderEvent, matching
  the existing demo's7-day return window. No guessed delivery date on legacy rows.
  Customer sees eligibility/reason from server. Paid/free delivered orders qualify;
  COD awaiting settlement needs explicit collection first. No fake COD receipt.
- One open return request per order, with one or more selected order-item IDs and
  positive quantities, reason3–300 chars, UUID requestKey. Owner isolation; immutable
  payload hash prevents changed retries. Requested+approved holds quantities; rejected
  releases them; received consumes them permanently. Historical partial returns are
  retained. New requests allowed after receipt/rejection if still within window.
- Allocate merchandise net total (subtotal-discount) deterministically across
  original items sorted by ID using cumulative proportional integer floors.
  For a partial quantity use cumulative line net entitlement minus prior received
  entitlement. One open case prevents overlapping reservations/rejected-case drift.
  Shipping is retained for a post-delivery return. Zero entitlement needs no money
  transaction. Server quotes/persists exact VND; admin cannot override it.
- REQUESTED -> APPROVED/REJECTED; APPROVED -> RECEIVED. Version and order locks,
  immutable decision/receipt actor/timestamps and audit in same transaction.
  Receive restores only accepted quantities exactly once. When all items received,
  order RETURNED and a new OrderEvent; carrier's historical DELIVERED is unchanged.
  Received amount is a refund entitlement, not proof of money being returned.
- Customer may cancel PENDING; admin may cancel PENDING or CONFIRMED with reason
  and expectedVersion. Cancel restores inventory/quota once. Pending VNPay attempts
  must be reconciled first. Paid money remains PAID and becomes a refund obligation;
  unpaid/free payment cancels. No direct cancellation after dispatch.
- Public order response includes safe return history and eligibility. Admin includes
  actor IDs and return versions. Return and cancellation notes are customer-visible.
  Existing zero-discount/no-history responses remain parse-compatible.
- Actual COD/VNPay refund receipts, partial refund payment status, provider-safe
  retries/query/review and paid cancellation settlement are next milestone; do not
  claim these entitlements as executed refunds.

## Implementation map and checks

- [x] Pure allocation utility + tests RED->GREEN: fractional rounding, zero total,
  multiple lines, repeated partial quantities, total entitlement never above net.
- [x] Real-PG API tests RED: owner/admin access,7-day/paid/delivered eligibility,
  invalid quantities, one open case, idempotency/concurrency, exact discounted
  snapshots, version conflicts, rejection release, receive stock once, audit
  rollback, paid/unpaid cancellation and unresolved VNPay attempt block.
- [x] Schema/additive migration and returns module; shared cancellation helper;
  order history/public/admin includes. Dedicated test DB migrate; full checks.
- [x] Customer request/quote/history and admin approve/reject/receive/cancel panels,
  repository/decoder tests and widgets for failure/reload and entitlement disclosure.
- [x] Real Chrome request->approve->receive partial case + paid cancellation,
  independent review, regressions, business backup/migrate/fingerprint/smoke/docs,
  commit. No external money movement in this milestone.
