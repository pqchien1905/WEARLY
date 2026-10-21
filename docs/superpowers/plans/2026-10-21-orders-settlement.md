# Shipping snapshot and COD settlement implementation plan

Use `executing-plans` inline. Spec: `docs/superpowers/specs/2026-10-21-local-completion-design.md`.
This is milestone two of the active full local completion goal.

## Constraints and interfaces

- Preserve existing data and integer VND arithmetic. Migration is additive; no seed/reset.
- `Order.shippingMethod` is `standard|express`, persisted at checkout. Backfill the
  historical50,000 fee as express, other known fees as standard. No fee inference in new UI.
- `POST /admin/orders/:id/settle-cod` accepts `{amount:string, reference:string,
  expectedVersion:number}`; only an authorized admin, delivered COD and exact amount
  can settle. Reference is trimmed3–100 characters. Delivery alone remains unpaid.
- Immutable `PaymentSettlement`: one per payment; amount, reference, actorId, settledAt.
  Same order/amount/reference retries return the receipt even if the version is stale;
  other repeats conflict. Transaction updates payment, order version and audit atomically.
- Admin detail includes receipt; customer payment exposes status only. Summary adds
  all-time paid amount/order count and delivered unpaid COD amount, as VND strings.
- Modal uses existing accessible controls, pending lock, canonical reload on conflicts.

## Task 1: Shipping snapshot

Files: Prisma schema/new migration, orders.service, commerce_json, remote commerce tests.
1. Add backend checkout assertion of stored express method; run and observe absent field.
2. Add frontend test with express+non50,000 fee; observe incorrect method inference.
3. Add checked column/backfill, store dto method, decode explicit method strictly,
   update server fixtures. Generate and migrate only dedicated test DB.
4. Run commerce backend/frontend tests. Expected: all pass and unknown method rejected.

## Task 2: Settlement and reporting API

Files: new settlement E2E, admin DTO/controller/service, Prisma migration, audit enum.
1. Add real HTTP+PG tests: unauthenticated/customer denied; invalid and stale inputs;
   pending/cancelled/nonCOD refused; exact delivered COD succeeds; conflicting and
   concurrent same-reference replay; no double receipt/audit; forced audit failure rolls
   all writes back. Report totals delta includes only paid/eligible receivables.
2. Run and observe404/missing functionality. Add model/constraints, DTO, transaction,
   endpoint and summary. Keep original payment-status transitions unchanged.
3. Run full backend lint/build/unit/E2E sequentially. Expected: all pass.

## Task 3: Admin UI and local migration

Files: remote_admin, admin_pages, admin_activity, widget/repository tests, setup/progress.
1. Write widget tests for delivered unpaid action, amount/reference validation, successful
   receipt display, duplicate click during pending request and canonical reload on409.
   Add dashboard test for formatted amount and receipt-free pending delivery.
2. Observe RED; implement modal/API call/receipt and all-time summary cards.
3. Format/analyze/full Flutter tests and web build. Expected: no new issues, all pass.
4. Backup business DB and apply reviewed additive migration; verify data preservation
   and readiness on compiled app. Independent milestone review, fix important findings,
   update ledger and commit. No actual COD receipt is fabricated in business data.

## Review focus

Race/retry double collection; wrong actor or untrusted body; unpaid delivered revenue;
partial writes on audit failure; shipping fee no longer determines fulfillment method.

Pre-flight: Task1 produces method required by Task3 decoder. Task2 produces the receipt
and summary consumed by Task3. Complete backend migration before running strict UI.
Full VNPay/shipment/return/refund features remain subsequent milestones.
