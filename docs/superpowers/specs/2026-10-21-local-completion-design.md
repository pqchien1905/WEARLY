# WEARLY local completion

## Authority and intent

The user asked to complete every gap identified in the 21 October audit. They then
specified local execution only, Gemini AI, VNPay virtual payments, delegated the
shipping choice, and accepted explicit COD settlement with amount/reference/actor
and an audit record. Delivery never implies payment. Keep Flutter, NestJS,
PostgreSQL, Redis/BullMQ and MinIO. This document supplements the original
`fashion_ai_commerce_agent_spec (1).md` with those current decisions.

## Required outcomes

1. Native local setup starts reliably with current schema, bounded health checks,
   UTC database connections and accurate readiness. Back up business data before
   additive migrations; no reset, seed overwrite or blind historical time shift.
2. Orders persist shipping method and commercial snapshots. Add explicit COD
   settlement, shipment tracking, failed delivery, authorized cancellation,
   return/refund workflows, customer-visible history and inventory compensation.
3. Promotions support fixed VND and percentage discounts, expiry, minimum spend,
   total/per-customer limits and transactional redemption. Backend computes totals.
4. VNPay sandbox payment initiation, signed callbacks, amount/order/provider
   validation, replay protection, retry/query reconciliation and test refunds.
   Browser redirect alone never marks an order paid. No real charges.
5. Shipping uses a local carrier simulator by default, visibly labelled as a
   simulator, with persistent tracking and operator-driven events. Select GHN
   sandbox as the external adapter if credentials are available; never create
   physical shipments. The user delegated this reversible local default.
6. Gemini Stylist selects valid active catalog products and checks price/stock.
   Gemini image editing supplies simulated try-on using consented private inputs
   plus the selected garment. Implement actual backend adapters and frontend
   repositories, quota/cost visibility, bounded calls, job idempotency and deletion.
   Without credentials, report configuration status honestly, never fake AI output.
7. Local email inbox and persistent support requests work without external mail
   delivery. Password recovery and order notifications are delivered to that inbox.
8. Role-scoped staff operations, useful sales/settlement/inventory reports, before/
   after audit details without sensitive payloads, and safe browser session renewal.
9. Local deployment scripts, CI checks, error/queue monitoring, backup/restore,
   repeatable customer/admin/browser acceptance and updated operator documentation.
10. Configurable store identity/policies, discoverable product HTML metadata and
    sitemap readiness; retain noindex for the local demonstration. Public domain,
    production TLS, off-host production backups and real-money delivery are outside
    the user's revised local-only deployment scope, not silently assumed complete.

## Implementation decisions

- Extend existing modules and design tokens; keep changes additive and reviewable.
- Use integer VND, transaction retries, immutable receipts and optimistic versions.
- Treat UTC as an internal storage/connection contract; display Asia/Bangkok dates.
- Existing shipping fees are 30,000 standard, 50,000 express, standard free at
  1,500,000. Persist the choice; legacy backfill may infer only known old fees.
- Gemini and VNPay secrets stay in backend environment files, never frontend.
- Current source/DB mismatch and recovery timezone failures are confirmed audit
  baselines, not reasons to stop the authorized repair work.
- Execute inline with TDD and independent review of completed logical milestones.
  User's A-Z instruction authorizes implementation of the audit remediation; no
  repeated approval gate for these reversible local changes.

## Verification and completion

Preserve every requirement above in a progress ledger. Each feature needs relevant
unit/integration/widget/browser evidence, including failure/retry/authorization.
Recheck business data after local migration and restore a backup separately.
External Gemini/VNPay/GHN acceptance requires configured test accounts and observed
provider responses; mock adapter tests alone do not prove that acceptance.
The overall goal stays active while any required local workflow is incomplete.

## Provider references

- https://sandbox.vnpayment.vn/apis/docs/thanh-toan-pay/pay.html
- https://ai.google.dev/api/generate-content
- https://ai.google.dev/gemini-api/docs/generate-content/image-generation
- https://developer.ghn.vn/en
