# Persistent local shipment tracking

BASE ab93b68. Execute inline with TDD and one independent review. Binding design:
`docs/superpowers/specs/2026-10-21-local-completion-design.md`.

## Decisions

- Default carrier is `local_simulator`; every tracking view says “Mô phỏng vận
  chuyển local”. No external shipment request, real tracking claim or automatic
  progress timer. GHN sandbox remains optional when test credentials exist.
- Existing admin CONFIRMED->SHIPPED creates one shipment with an immutable
  LOCAL-UUID tracking code and IN_TRANSIT event. Existing delivered action appends
  DELIVERED to an existing shipment. Legacy orders are not given invented history.
- New admin shipment-events endpoint accepts eventKey UUID, expectedVersion,
  status and optional customer-visible note (300 characters). Lock order, validate
  version/transition, persist event+audit+order changes in one serializable tx.
  Replaying an eventKey with identical payload returns canonical order; different
  payload conflicts. No public callback can change local shipment state.
- States: IN_TRANSIT -> OUT_FOR_DELIVERY or DELIVERED; OUT_FOR_DELIVERY -> DELIVERED
  or DELIVERY_FAILED; IN_TRANSIT may also fail; DELIVERY_FAILED -> IN_TRANSIT retry
  or RETURNED. Final states cannot advance. Failure leaves order SHIPPED; physical
  return changes order RETURNED and restores all inventory exactly once. Unpaid
  COD becomes CANCELLED; paid VNPay remains PAID pending explicit refund workflow.
  Coupon use stays consumed once shipped. Delivery never settles COD.
- OrderEvent records new order creation, confirmation, shipping, delivery, return
  and cancellation. No invented historical timestamps. Owner order API exposes
  event/status/note/time but not actor IDs. Admin retains actor IDs.
- UI uses existing components. Customer and admin detail show persistent code,
  carrier status, UTC+7 event times and notes. Admin can retry failed delivery or
  confirm goods physically returned; return action explains stock/payment effects.
- Authorized cancellation beyond pending and customer return/refund requests are
  the next milestone; keep those financial rules separate from carrier events.

## Steps

- [x] RED real-PG API: admin/ownership, transitions, payment gating, immutable
  code/events, no COD settlement on delivery, retries/concurrency/version, return
  stock exactly once, retained coupon quota, paid amount unchanged, audit rollback.
- [x] Add schema/migration, shipment service/controller and order history hooks.
  Migrate dedicated test DB; backend suites/lint/build GREEN.
- [x] RED widgets/repositories: tracking decoding/history, admin fail/retry/return,
  validation/conflict and customer-visible simulator label. Implement + full checks.
- [x] Chrome admin/customer acceptance using dedicated synthetic fixtures; review
  milestone and fix important findings with regressions.
- [x] Backup/migrate local business DB, fingerprint original data, smoke, document,
  commit. Keep overall A-Z objective open.
