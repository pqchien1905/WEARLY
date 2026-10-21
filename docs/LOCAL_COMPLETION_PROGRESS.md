# Local completion progress — 21 October 2026

Full objective: complete all audited gaps, with user's local-only scope, Gemini,
VNPay sandbox, delegated shipping and explicit COD settlement. Goal is ACTIVE.

## Milestones

- [x] Foundation: timezone, schema/readiness, local backup and migration.
- [x] Shipping snapshot, COD settlement, useful business reports.
- [x] VNPay sandbox local implementation and signed-fixture acceptance.
- [x] Transactional promotions and customer/admin UI.
- [x] Persistent local shipment tracking, failed delivery/retry and carrier return.
- [x] Authorized cancellation, customer returns and refunds.
- [x] Local email inbox, order notifications and persistent customer support.
- [ ] Staff roles/audit detail and persistent safe sessions.
- [ ] Gemini Stylist and private asynchronous try-on with frontend integration.
- [ ] Local tooling/CI/monitoring/recovery and store content/SEO.
- [ ] Customer/admin/browser acceptance and configured provider verification.

## Evidence and rulings

- Baseline branch dd16a3c; audit found native business DB 8/12 migrations and
  login/content500 while readiness200. Backend17 unit, Flutter317 pass;
  native80 E2E:78 pass/2 recovery timezone failures. UTC recovery9 pass.
- Ruling: user explicitly authorized A-Z audit remediation and then local-only
  execution. Preserve full local feature scope; production deployment is excluded
  by that later instruction. No repeated permission requests for local fixes.
- Ruling: implement inline, retain a durable ledger and request independent milestone
  review. Missing provider credentials do not stop independent work.
- Worktree `.worktrees/completion-2026-10-21`, branch `codex/completion-2026-10-21`.
- New baseline finding: Jest rootDir-prefixed test globs fail discovery under the
  nested Windows `.worktrees` path. Use root-scoped relative globs, then verify.
- Builder review: no important unanswered design questions. Provider credentials
  remain an external acceptance input; local coding continues.
- Foundation Task 1: RED confirmed timezone/recovery failures; GREEN 12/12
  database/recovery tests after forcing UTC in pg URL options for every pool member.
- Ruling: readiness checks generated required model columns and enum values, not
  a full schema/index/type diff. Migration validation remains a deployment check;
  the runtime probe catches the observed missing-table/column failures cheaply.
- Foundation Task 2: missing-table/column RED (readiness incorrectly200), GREEN
  real-PG/Redis tests, compiled API returned503 against pre-migration business DB.
- Native database backup: `.tools/local-completion-20261021/before-foundation-1792595758831.dump`
  (98,233 bytes; custom pg_dump archive and TOC verified). Applied four additive
  migrations to `wearly` (8→12). All24 preexisting business tables retain identical
  row counts and SHA256 fingerprints over their original columns. No reseed/reset.
- After migration: compiled readiness/content/products200, nonexistent-user login401
  (previously500), audit/catalog queries succeed. Full87 E2E,17 unit, lint/build pass.
- Root `.env.test` now targets native `wearly_test`: previous5433 configuration
  retained privately as `.tools/local-completion-20261021/previous-native-env.test`.
- Fixed test helper handling of benign native stderr under Windows PowerShell5.1.
- Restored that archive into isolated `wearly_local_restore_1792595955180_2bf4aaf3_test`:
  all24 original table fingerprints match, migrations8→12 pass, readiness/content/products200.
  Evidence stays private in `.tools/local-completion-20261021/restore-result.json`.
- Independent foundation review found2 important issues: unbounded DB work behind
  the readiness response deadline and search_path differing from Prisma's schema.
  Both reproduced RED; GREEN6 health tests after a server-side statement timeout,
  bounded transaction acquisition, one metadata query and explicit shared schema.
  The reviewer's tentative PowerShell failure finding was disproved; no change made.
- Latest foundation verification:89/89 E2E,17/17 unit, lint/build pass.
  A first E2E attempt overlapped Prisma generation and failed discovery; rerunning
  after build completed passed. Ruling: generation/build and dependent tests must
  be sequential. `--detectOpenHandles` health run passes and reports no leaked
  handle; normal focused runs sometimes print a delayed-exit warning then exit0.
  Existing pg concurrent-query deprecation warnings remain visible in full E2E.
- Follow-up review demonstrated a lost transport reply before transaction startup
  still held a shared pool connection. Real TCP-proxy regression RED (one retained
  connection), GREEN after readiness moved to its own short-lived pg connection:
  startup statement_timeout, client query/connect deadlines and owned socket destroy
  in finally. No health query uses the business pool. Seven health tests pass,
  including slow SQL, dropped replies, missing schema and alternate search_path.
- Ruling: replaces the transaction-based probe because Prisma's response deadline
  cannot cancel a stalled underlying transport. The per-request connection costs a
  local handshake but gives cleanup ownership and leaves business capacity intact.

- Foundation final:90/90 real E2E,17/17 unit, lint/build and diff check pass.
  Two review findings resolved with SQL-timeout and transport-stall regressions.

## Shipping / COD milestone

- Task1 RED: checkout omitted shippingMethod and Flutter inferred express from fee.
  GREEN:12 commerce E2E and10 remote-commerce tests. New checked column backfills
  historical50000 as express; all new orders persist the selected method.
- Task2 RED: missing settlement endpoint/reports. GREEN:5 real HTTP/PG tests cover
  authorization/validation, eligibility/amount/version, concurrent idempotency,
  received-versus-awaiting reporting and audit failure rollback. Delivery stays unpaid.
- Real concurrent settlement exposed P2010 wrapping PostgreSQL serialization conflict.
  Narrow retry recognition now unwraps only the known driver conflict; unit RED→GREEN.
- Task3 RED→GREEN:3 widgets exercise amount/reference validation, pending double click,
  successful receipt, canonical reload after409 and separate report amounts. Reporting
  formats aggregate VND strings directly, avoiding floating-point conversion.
- Latest checks:96/96 backend E2E,18/18 unit, lint/build pass; Flutter321 pass,
  2 opt-in skipped, analyze clean, web build passes. Chrome acceptance and milestone
  review/local business migration are still in progress.
- Review found unknown legacy fees would be guessed standard; ordered preflight now
  aborts before the backfill. RealPG temp-table test RED→GREEN for40000; known
  0/30000/50000 map correctly. Current business DB had zero legacy orders.
- Receipt timezone review resolved with explicit UTC+7 label; widget RED→GREEN.
- First Chrome acceptance exposed missing accessible receipt text (payment201,
  visual receipt present, semantics blank). Added SelectableText semantics label;
  accessible-name regression RED→GREEN. Full Chrome rerun in progress.
- Business backup `before-settlement-1792597220925.dump` (108,489 bytes) verified,
  migrations12→15 applied. All28 existing tables retain exact original-column
  counts/fingerprints; no business receipt fabricated. Ready/content/products200.

- Milestone2 final:98/98 backend E2E,18/18 unit; Flutter321 pass/2opt-in skips,
  analyze clean; real Chrome admin desktop/mobile pass including delivered?explicit
  COD collection?persisted receipt, no browser errors. Local ready/content/products200.
  All review findings resolved; log/screenshot evidence under `.tools/`.

## Next work: VNPay sandbox (research started)

- Checkpoint commits:16acc75 foundation;3901971 shipping/COD. Main workspace branch
  remains at363bea0; implementation remains in the isolated worktree until integration.
- Root backend/.env checked for presence only: GEMINI_API_KEY, VNPAY_TMN_CODE and
  VNPAY_HASH_SECRET are absent. Existing async credential question remains pending.
- Official provider HTML retrieved to private `.tools/vnpay-doc-0.html` (PAY) and
  `.tools/vnpay-doc-1.html` (querydr/refund); companion `.txt` files strip tags.
  Web open timed out, official indexed content and direct HTTPS fetch succeeded.
- Upcoming design must account for local callback reachability: authenticated
  querydr reconciliation is needed when the provider cannot reach local IPN.
  Return navigation alone must never mark paid. Persist attempt reference/create
  date; verify HMAC and merchant/reference/amount/status; guard callback/cancel races,
  retries and late successes. Sandbox URLs are fixed; no real-money endpoint.
- Checkout currently hardcodes COD, remote_orders request lacks paymentMethod,
  commerce_json rejects nonCOD, frontend sessions remain in memory. VNPay frontend
  return experience therefore depends on session restoration or retaining the
  original checkout tab; resolve that explicitly in the next milestone plan.
- No VNPay production code written yet. Full objective remains ACTIVE with all
  remaining milestones listed above; do not mistake a checkpoint for completion.

## VNPay sandbox implementation — 21 October 2026

- Added strict opt-in configuration, fixed sandbox checkout/query endpoints,
  HMAC-SHA512 protocol verification, exact VND scaling and UTC+7 gateway dates.
- PaymentAttempt persists15-minute references, retry/reconciliation and exception
  review flags. Owner-only start/query; signed public IPN; return redirect never
  settles. Cancellation/fulfillment are serialized with payment updates. Late or
  double success is retained without repeating inventory movements.
- Flutter selects VNPay, preserves checkout idempotency, opens a separate sandbox
  tab and queries verified payment status. Admin sees attempts and review flags.
  COD remains available. Setup documented in `docs/VNPAY_SANDBOX.md`.
- Review fixes RED->GREEN: both success/detail pages retain the gateway link across
  a delayed canonical reload; definitive PAYMENT_UNAVAILABLE unlocks checkout for
  COD fallback. Unknown503/lost responses still reuse the frozen request.
- Verified107/107 backend E2E,25/25unit,328 Flutter tests pass/2opt-in skipped.
  Chrome VNPay local-fixture flow passes desktop/mobile, popup, query, callback
  information page, reload/login and database assertions. Browser fixtures are
  explicitly synthetic and send no requests to VNPay.
- Backed up business DB to `before-vnpay-1792598826753.dump`, applied migration16,
  all29 original tables retain identical counts and original-column fingerprints.
  Business PaymentAttempt is empty; no payment fabricated. Ready/content/products/
  payment-methods smoke200 using compiled worktree API.
- Root backend/.env presence-only check still found Gemini/VNPay keys absent after
  user said they will configure them. Real provider acceptance remains pending;
  all other local milestones remain in scope.
- Final VNPay checks: lint/build/analyze clean; COD Chrome regression also passes
  after the shared checkout changes. Review found no deferred minor issues.

## Promotions — 21 October 2026

- Fixed/percentage coupons, validity windows, minimum spend, discount caps,
  global/per-customer quotas, cart-version preview and exact order snapshots.
  Serializable order creation locks the coupon; cancellation returns usage.
- Ruling: zero-total orders use free/PAID amount0 and no receipt or gateway
  attempt. Cost if business policy changes: reject zero-total discounts instead.
- Existing order-total SQL constraint required an ordered follow-up migration;
  already-applied test migration checksums were preserved. Optional DTO fields
  are filtered before merging an update to avoid overwriting with undefined.
- Customer quote/retry/discount summaries and versioned admin editor implemented.
  Real Chrome passes admin coupon creation, mobile checkout, order persistence,
  cancellation, released quota and reload/login. No business fixture created.
- Independent review found two important issues, both RED->GREEN: unchanged
  admin date fields now preserve seconds/milliseconds; free orders no longer
  require VNPay availability. No deferred minor findings.
- Final116/116 E2E,26/26unit,333 Flutter pass/2 opt-in skips; lint/build/analyze
  clean. Logs and Chrome screenshots stay in private `.tools/` artifacts.
- Backup `before-promotions-1792600245978.dump` verified; business migrations16->18
  applied. All30 original tables retain exact original-column fingerprints/counts;
  CouponRedemption is empty. Operator guide: `docs/PROMOTIONS.md`.

## Shipment tracking — 21 October 2026

- Added one local-simulator shipment per newly dispatched order, immutable
  tracking code, ordered event history and customer-visible notes. Order history
  records new checkout/confirmation/dispatch/delivery/cancellation/return actions.
  Public responses omit staff identifiers; admin retains them.
- Failed delivery can retry or return. Physical return restores all order stock
  exactly once; unpaid COD is cancelled, paid amounts remain paid for explicit
  refund handling. Shipped coupon use remains consumed. Delivery never collects COD.
- Ruling: no invented legacy history or tracking backfill. Cost: legacy shipped
  orders without tracking need a separately designed adoption flow for simulated
  failed returns; current local business data contains no such orders.
- RED7 real-PG API cases -> GREEN; four new UI tests cover parsing, UTC+7/history,
  simulator disclosure, return confirmation and conflict reload. Existing remote
  checkout regression exposed the removed cancellation panel; restored, GREEN.
- Review's one important finding: uppercase UUID idempotency keys compare
  differently after PostgreSQL normalization. Concurrent uppercase return RED409
  -> GREEN201/201 after normalizing keys; one stock movement/event. No deferred minors.
- Chrome passed failure/retry/return plus a delivered-unpaid COD order, customer
  code/history/notes, reload/login and375/1440px. Screenshots visually inspected.
- Final123/123 E2E,26/26unit,337 Flutter pass/2opt-in skips; lint/build/analyze clean.
  Backup `before-shipments-1792600965308.dump`, business migration18->19; all31
  original tables fingerprint-verified and preserved; no shipment fabricated.
  Ready/catalog/content200. Setup/operation: `docs/SHIPMENTS_LOCAL.md`.

## Refund research checkpoint

- Official VNPay querydr/refund docs rechecked21October2026. Refund response00 is
  request success; transaction05/06 remain processing,09 rejected. Only verified
  final success may count as refunded. Preserve durable request identity; ambiguous
  network outcomes must not blindly resend a monetary request. Reference:
  https://sandbox.vnpayment.vn/apis/docs/truy-van-hoan-tien/querydr%26refund.html

## Returns and cancellation — 22 October 2026

- Persisted owner return requests, 7-day recorded-delivery eligibility, exact
  discounted merchandise allocation, versioned decisions and physical receipts.
  One open case; replay-safe partial quantities and inventory compensation.
- Owner pending/admin pre-dispatch cancellation share an order-locked helper.
  Collected money remains recorded; unresolved VNPay attempts block cancellation.
  No actual refund execution in this milestone; that remains next.
- Chrome customer quote/request -> admin approve/receive -> customer reload passed
  at mobile/desktop; paid cancellation preserved PAID. Screenshots inspected.
- Independent review's important retry/remount defect reproduced RED, then fixed:
  restored immutable pending draft and bypassed editable-form validation on replay.
  Minor full-return eligibility message also RED->GREEN. No deferred findings.
- Final131/131 E2E,29/29unit,343 Flutter pass/2opt-in skips; lint/build/analyze clean.
  No backend edits or client generation overlapped the final backend suite.
- Backup before-returns-1792603472127.dump verified; business migrations19->20.
  All34 original tables retained exact row counts/original-column fingerprints;
  ReturnRequest empty. Compiled ready/catalog/content200 and private routes401.
- Guide: docs/RETURNS_LOCAL.md. Full A-Z goal remains ACTIVE; refunds, AI, local
  mail/support, roles/sessions, operational tools and final integration remain.

## Refunds — 22 October 2026

- Durable source-specific refund ledger: COD explicit receipt, VNPay sandbox
  persist-before-send, replay never sends money twice, processing/unknown amounts
  remain reserved, verified query and rejection release. Partial refunds retain
  original collection/attempt evidence; additional paid attempts refund separately.
- Exact cancellation/carrier-return versus customer-return entitlement; no refund
  inventory mutation. PARTIALLY_REFUNDED is handled across payment/return guards.
  Admin/customer history, immutable browser retry after remount and source details.
- Review fixed two important findings with RED->GREEN regressions: signed initial
  response now matches request-specific OrderInfo; one unresolved refund/source;
  legacy REFUNDED without ledger separated from determined net balance. Admin-only
  provider request/source IDs and refunded fulfillment message also corrected.
- Final141/141 E2E,40/40unit,350 Flutter pass/2opt-in skips; lint/build/analyze clean.
  Chrome after review passes discounted partial COD receipt, paid cancellation,
  signed-fixture VNPay PROCESSING->query->SUCCEEDED, source/stock assertions and
  customer reload at mobile/desktop. Final screenshots inspected. Real sandbox
  provider credentials/acceptance remain pending; no external money sent.
- Backup before-refunds-1792604961374.dump verified; business migration20->21.
  All36 original tables preserved by count/original-column fingerprints; Refund0.
  Compiled readiness/catalog/content200 and protected resources401. Guide:
  docs/REFUNDS_LOCAL.md; reused tools/test-frontend-api.cjs --refunds acceptance.
- Remaining full scope: local inbox/order mail/support, staff roles/audit/session
  renewal, Gemini Stylist/try-on, local operations/CI/monitoring/recovery and store
  metadata/SEO, provider acceptance and final worktree integration. Goal ACTIVE.

## Local inbox and customer support — 22 October 2026

- Pinned/checksummed native Mailpit with loopback SMTP/HTTP, persistent private
  SQLite, no relay/forwarding and sanitized inherited settings. Captures local
  recovery, transactional order/payment/return/refund notices and support replies.
- Durable guest receipt, UUID/payload replay, private admin replies and versioned
  close/reopen. Transactional immutable mail outbox, lease ownership, five bounded
  attempts, safe error codes, status UI, responsive contact/admin screens.
- Independent review found three important defects; all reproduced RED and fixed:
  throttled retries retain uncertain keys; pending replies remain reconcilable after
  closure; slowly progressing SMTP cannot outlive an absolute deadline and worker
  shutdown destroys the owned socket. No deferred minor findings or re-review.
- Final153/153 real E2E,43/43unit,357 Flutter pass/2 opt-in skips; lint/build/analyze
  clean. Final Chrome support verifies guest receipt, admin reply, actual native
  inbox/order mail and mobile/desktop/reload. Recovery Chrome verified actual
  inbox link, URL scrub, one-use token and old-password/session invalidation.
- Backup before-mail-support-1792607229836.dump verified; business migrations21->22.
  All37 original tables retain exact original-column fingerprints/counts;
  SupportTicket remains empty. Compiled ready/catalog/content200, protected401.
- Worktree private environment enables local inbox/recovery. Initial config smoke
  caught dotenv stripping an unquoted hash fragment; corrected and smoke passed.
  Recovery and VNPay example URLs now quote fragments. Root environment remains
  under the user's control until final integration; no provider secret printed.
- Ruling: reviewer exclusions for earlier commerce, wider audit and configured
  providers remain assigned to their milestones, not waived requirements. Business
  migration was completed after review. Cost if wrong: later acceptance can reveal
  cross-milestone work and the overall goal must remain active.
- Ruling: immutable implementation checkpoint7956c29 preceded the single review;
  verified review fixes follow in a separate commit. Cost: two commits per milestone.
- Ruling: automatic approval review blocked the combined Mailpit stop/restart
  persistence check with "blocked by policy". No bypass attempted; persistence is
  configured, but restart acceptance remains unverified. Cost: crash/restart
  persistence is not claimed as proven. Guide: docs/MAIL_SUPPORT_LOCAL.md.
- Full A-Z goal remains ACTIVE: staff permissions/audit, persistent sessions, Gemini,
  operations/CI/recovery/SEO, configured providers and final integration remain.

## Staff and audit — completed, 22 October 2026

- Task1 backend: explicit role/capability matrix and default ADMIN-only guard,
  versioned staff lookup/change, current-actor recheck, session revocation, atomic
  audit, last-active-admin protection under concurrent edits. Registration cannot
  grant roles; customer listing excludes staff. Focused7 and full160 E2E GREEN,
  lint/build clean. TestDB migration23 only; business DB remains22 until final review.
- Staff last-admin tests own a random schema inside the dedicated_test database;
  all unrelated accounts stay untouched. Original database-create setup lacked
  CREATEDB; switched to isolated-schema Prisma override only in tests.
- Full verification caught two expected integration updates: audit response now
  includes details; test runner must disable local feature flags before fixtures
  opt in, so enabled recovery in local.env cannot break test-specific origins.
- UI permission gates, safe detailed audit, Chrome, review and business migration
  remain pending. Persistent browser sessions are a separate next milestone.
- Task2 safe audit now implemented: explicit per-action before/after scalar fields,
  exact Decimal/date serialization and no personal messages/addresses/credentials.
  Captured in the mutation transaction for catalog, inventory, commerce, promotions,
  content, support and staff. Taxonomy/image events retain action/target only, and
  older rows remain empty rather than inventing history. RED3 API assertions and
  missing sanitizer -> GREEN10 focused/3unit; final163 E2E/46unit, lint/build clean.
- Task3 UI: ten new login/route/control/staff conflict/self-demotion/audit tests;
  full367 Flutter pass/2 opt-in skips and analyzer clean. Unknown-route fallback
  formerly crashed because StoreShell read missing GoRouterState in errorBuilder;
  reproduced RED and replaced with a standalone fallback. Existing admin settings
  deep links retain their unavailable-screen behavior; regression3 RED->GREEN.
- Chrome staff PASS: UI grants roles, warehouse inventory+2 and dispatch/delivery,
  no COD collection, denied staff/money API, support reply and reload, then demotion
  revokes current access. 375/1440 screenshots visually inspected. Fixture-only
  data cleanup; no business account changed. Browser selector corrected to actual
  Flutter accessibility button label; no product workaround. Review/migration pending.
- Final review bfbef9c..77c3d34: no critical/important reported; one minor promotion
  amount-unit issue regraded important because percentages shown as VND misstate
  financial history. One tested fix pass: PERCENT/FIXED changes and same-number
  unit changes RED->GREEN. Full368 Flutter pass/2 skips, analyzer clean. Backend
  unchanged since163 E2E/46unit/lint/build PASS. No deferred minor or re-review.
- Backup before-staff-audit-1792609176819.dump verified; business migrations22->23.
  All40 original tables retain exact counts/original-column fingerprints; no new
  staff roles assigned. Compiled readiness/catalog/content200 and private401.
  Guide: docs/STAFF_LOCAL.md. Persistent browser sessions are next; full goal ACTIVE.
- Ruling: preserve the existing ADMIN-only unavailable settings/monitoring routes
  until their assigned milestones, and use a standalone unknown-route fallback.
  Cost: the fallback intentionally has no store chrome. No unimplemented screen
  is claimed complete. Schema isolation replaces unavailable CREATEDB for tests;
  cost: fixture migrations run once per owned schema, never change business users.
