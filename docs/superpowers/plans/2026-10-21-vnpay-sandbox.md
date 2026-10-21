# VNPay sandbox implementation plan

Use `executing-plans` inline and TDD. Spec: `docs/superpowers/specs/2026-10-21-local-completion-design.md`.

**Goal:** Customer can choose VNPay sandbox, open a signed checkout, then verify the
result from the local API; payment is never inferred from browser navigation.
**Architecture:** Fixed sandbox gateway adapter, persisted attempts, serializable
order/payment mutation and signed IPN/querydr verification. Retain COD behavior.
**Stack:** NestJS/Prisma/PostgreSQL, Flutter Web; no new provider SDK.

## Constraints and decisions

- Enable explicitly with VNPAY_ENABLED=true, TmnCode8alphanumeric, hash secret,
  API return URL and storefront return URL. Secret stays backend; missing config
  leaves COD usable and returns a clear unavailable response for VNPay.
- Fixed HTTPS sandbox checkout/query URLs. Local return points to the API and
  redirects only to the configured storefront. No caller-supplied redirect URL.
- Store PaymentAttempt(id/reference, paymentId, amount, createdAt/expiresAt, IP,
  status, transactionNo, lastQueryAt, reviewRequired). Reuse pending attempts.
  Expired but unverified attempts must reconcile before retry/cancel; a signed
  expired not-found query can close an abandoned attempt. Late success is still
  recorded and flagged for refund/review if the order was cancelled/already paid.
- Integer VND multiplied by100 as BigInt. Gateway maximum12digits after scaling.
  HMAC-SHA512 over encoded sorted pay/IPN fields; pipe-separated querydr signatures.
  Reject arrays, malformed signatures, wrong merchant/reference/amount/transaction.
- Only owner can start/reconcile. Admin cannot confirm an unpaid VNPay order.
  Cancellation must lock the order and refuse an unresolved active payment or paid
  VNPay until the refund workflow. Signed IPN is public but verifies before mutation.
- Return endpoint only validates signature and redirects to a result information
  page. Checkout opens in a new tab so the current in-memory session survives;
  persistent session restoration remains the later full-scope session milestone.
- No real VNPay acceptance claim without user's sandbox credentials and observed
  gateway responses. Use independent signed HTTP fixtures for failure-path tests.

## Task 1: Protocol adapter and configuration

Files: integrations/payments/vnpay.provider.ts, env.validation.ts, provider/env tests.
Interfaces: enabled/assertAvailable, checkout(attempt):URL, verifyIpn(query):event,
query(attempt):verified result. Query timeout5seconds; bounded64KiB response.

- [x] RED tests for sorted encoding/signature, exact amount/UTC+7 time, return URLs,
  malformed/tampered/duplicate fields, query response signature and timeout/error.
- [x] Implement adapter and strict configuration; GREEN targeted and full unit tests.

## Task 2: Persisted workflow and API

Files: Prisma attempt migration, new payments module/controller/service, order DTO/
service/module, admin status guard, payment E2E and existing commerce fixtures.
Routes: GET payments/methods; POST payments/orders/:id/start; POST .../reconcile;
GET payments/vnpay/ipn and .../return. Responses contain state, expiry, sandbox URL.

- [x] RED real HTTP/PG tests: disabled provider has no cart effects; method belongs
  to idempotency hash; owner/admin authorization; same-attempt start concurrency;
  valid/wrong amount/tampered/duplicate callbacks; failed→retry; local signed query;
  return alone unpaid; cancel/payment and admin-confirm races; late/double success
  retained for review and never double inventory movement.
- [x] Implement transactions and mapper, generate/migrate test DB, GREEN suites.

## Task 3: Customer/admin UI and acceptance

Files: remote payment repository/providers, checkout selector, payment panel/order
decoder, external-window helper, result information route, admin attempt visibility.

- [x] RED tests: VNPay request snapshot survives retries; disabled provider feedback;
  unpaid status and gateway link; explicit reconciliation updates canonical order;
  errors remain pending; sandbox-only links and callback page makes no paid claim.
- [x] Implement and verify widgets/analysis/build plus Chrome checkout/payment flow
  with local signed provider fixtures (never claim those are real provider responses).
- [x] Review whole milestone, resolve findings, backup/migrate business DB without
  fabricating payments; docs/config instructions, commit and ledger.

## Review focus

Unauthenticated forged return; cross-order transaction reuse; duplicate retries;
expired link versus late success; cancellations restoring stock during payment.
Pre-flight: Task1 protocol feeds Task2; Task2 response schema feeds Task3. Refund
operations use stored attempts in a subsequent milestone; flagged exceptions remain
visible until that workflow is complete.

Sources: https://sandbox.vnpayment.vn/apis/docs/thanh-toan-pay/pay.html and
https://sandbox.vnpayment.vn/apis/docs/truy-van-hoan-tien/querydr%26refund.html
(official documentation retrieved21October2026; private local copies in .tools).
