# Local completion progress — 21 October 2026

Full objective: complete all audited gaps, with user's local-only scope, Gemini,
VNPay sandbox, delegated shipping and explicit COD settlement. Goal is ACTIVE.

## Milestones

- [x] Foundation: timezone, schema/readiness, local backup and migration.
- [x] Shipping snapshot, COD settlement, useful business reports.
- [ ] VNPay sandbox, promotions, shipment tracking, cancellations/returns/refunds.
- [ ] Local email/support, staff roles/audit detail, persistent safe sessions.
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
