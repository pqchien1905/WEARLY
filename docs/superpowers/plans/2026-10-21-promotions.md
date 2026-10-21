# Transactional promotions

Execute inline with `executing-plans` and TDD. Binding spec:
`docs/superpowers/specs/2026-10-21-local-completion-design.md`.
BASE: d7b7815. VNPay local implementation is already committed; do not redo it.

## Decisions

- Extend existing Coupon: immutable uppercase ASCII code3–32, kind FIXED/PERCENT,
  amount as integer VND or integer percent1–100, active, startsAt/expiresAt,
  minSubtotal, optional maxDiscount and usageLimit, perUserLimit(default1), version.
  Existing coupons remain FIXED with their existing amount and activation state.
- One coupon per order, discount on merchandise only. Percentage rounds down to
  whole VND, caps at maxDiscount and subtotal. Shipping uses original subtotal,
  preserving the existing free-shipping policy. Backend is authoritative.
- Persist immutable Order.discount and couponCode plus CouponRedemption unique by
  order. Lock coupon while checking global/per-user counts and creating redemption.
  Roll back coupon, inventory and cart changes together if any step fails.
- Pending order cancellation releases its redemption in the same transaction;
  fulfilled/returned orders keep the historical usage (refund workflow later).
- A zero-total order has provider `free`, amount0 and PAID (nothing to collect),
  never creates a gateway attempt or COD receipt. Ordinary positive totals retain
  the chosen COD/VNPay provider. Show “Không cần thanh toán” for a free order.
- Idempotency adds couponCode/expectedDiscount only when a coupon is supplied;
  preserve old request hashes otherwise. Replays return the immutable order even
  after coupon expiry/deactivation. Different coupon/method cannot reuse a key.
- Preview reads the authenticated cart and version, returns exact discount/total;
  checkout verifies expectedDiscount and cartVersion again. Changing cart/shipping
  clears the quote; uncertain retries retain original code/amount/key.
- Admin create/edit/deactivate uses versions and audit. No deleting used coupons.
  Dates entered/displayed with UTC+7 labels. Codes cannot be renamed after creation.

## Task1: Backend money, persistence and API

Files: schema + additive migration, promotions module/DTO/service/controllers,
orders DTO/service/module, money and real-PG tests. Interfaces:
POST promotions/preview {code,shippingMethod,cartVersion}; returns
{code,discount,subtotal,shipping,total,cartVersion}. Admin GET/POST promotions,
GET/PATCH promotions/:id; edit body includes expectedVersion. Order carries
discountVND string in `discount` and nullable couponCode.

- [x] RED pure money tests: percent flooring, cap, subtotal ceiling, bounds.
- [x] RED API/PG: authorization/validation, preview no redemption, validity dates,
  spend threshold, per-user/global quotas under concurrency, failed-order rollback,
  exact snapshot/idempotency, expiry replay, version conflicts, cancellation release,
  free order, discounted VNPay amount, audit atomicity.
- [x] Implement/generate/migrate dedicated test DB. Full unit/E2E lint/build GREEN.

## Task2: Customer/admin UI

Files: domain/order mapper, promotion repository/providers, checkout quote input,
order summary discount/coupon display, remote admin promotion page and editor.

- [x] RED repository/widget tests for exact retry snapshot, quote invalidation,
  server errors, discount totals/free provider, admin version conflicts and limits.
- [x] Implement with existing UI components. Analyze/full Flutter suite GREEN.

## Task3: Acceptance and review

- [x] Real Chrome admin creates a coupon; customer previews/redeems it; verify
  persisted totals/counts; cancellation releases usage. Dedicated test DB only.
- [x] One independent whole-milestone review; fix important findings RED->GREEN.
- [x] Backup/migrate business DB, preserve old table data, ready smoke; operator
  docs/progress/commit. Provider credentials remain unrelated to coupon acceptance.

Expected checks: existing COD/VNPay requests remain compatible, original data
unchanged except additive defaults, no duplicate quota consumption or fabricated
financial receipts. No hidden production deployment or external messages.
