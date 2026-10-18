# Execution ledger — docs/superpowers/plans/2026-10-18-wearly-backend.md

- Audit: no AGENTS.md or .git found. Portable Node 24.22.0, Git and Flutter present under .tools. Docker CLI/Desktop absent.
- Frontend: apps/storefront; 5 domain files, 6 mock implementations, Riverpod/go_router, web platform only. Existing UI supports catalog/cart/checkout/account/addresses/style/orders/admin/stylist/try-on.
- Ruling: execute inline in existing directory per user; no synthetic Git history or worktree.
- Ruling: preserve visual tokens/components; frontend-design applies as a preservation constraint, no redesign requested.
- Ruling: prisma.config.ts is official Prisma 7 config; generated client uses explicit CJS module format for NestJS 11 tooling.
- Ruling: foundation COD decrements stock at order confirmation and restores only on pending cancellation; reserved-stock/payment-expiry architecture deferred until real payment gateway.
- Ruling: new master prompt /api/v1, /orders and /users/me replace earlier proposed /v1 and /orders/checkout.
- Ruling: integer-valued Decimal(14,0) VND serialized as exact decimal strings; Flutter converts only safe integer values.
- Pre-flight: Task 2 supplies catalog JSON consumed by Task 5; field names mapped explicitly. Task 1 Prisma models feed Tasks 2–4. Cart mutation and checkout share a transaction lock. No competing app/state architecture.
- Baseline Flutter test: sandbox denied process access; approved rerun passed 174/174.
- User follow-up authorized installing missing software and supplied GitHub remote; author pqchien1905 + noreply approved. Git initialized and baseline committed as 9033bce before moving; all 102 source/assets hashes preserved.
- Installed Git2.55.0.5, WSL3.0.3, Docker Desktop4.95.0. Existing Node24.22 and Flutter3.47.7 added to user PATH.
- Windows features activation requires reboot (RestartNeeded=true); compose config passed, Engine/compose up failed because VMP not active. No automatic restart.
- Ruling: temporary PostgreSQL18.4 under ignored .tools enables real DB testing while Compose PostgreSQL17 awaits reboot. Initial WIN1252 locale failed Vietnamese strings; created new UTF8 DBs without dropping existing DBs.
- Task1: schema22 models, two migrations validated/applied to fresh DBs, seed run twice creates32 products/256SKUs without resetting inventory.
- Tasks2–3: core API build/lint/unit4 and E2E9 passed; last-SKU race, duplicate checkout, cancellation replay, refresh replay, role injection/ownership covered. Added explicit order-total overflow regression after observing500; validation now rejects before mutation.
- Task4: AI provider Disabled, queue/outbox/worker/storage architecture implemented; Redis runtime tests blocked by Windows reboot. No real AI/upload/payment claim.
- Task5: remote catalog6 tests, full Flutter180 tests pass,1 live API test passes separately; analyze clean; release Web build passes.
- Task6: architecture/database/API/setup/migration docs and Mermaid sources created; independent read-only final review in progress.
- Dependency audit: patched Swagger js-yaml override to5.4.1; npm audit --omit=dev reports0 known vulnerabilities.
- Final review: no Critical/Important findings. Minor null DTO bypass and test-helper environment leakage corrected. Null inputs now400; E2E10 pass; helper run confirms Environment restored=True.
- Deferred scope rulings: Docker/Redis/container/worker runtime require Windows reboot; real upload/AI/payment and mobile builds explicitly remain unverified. No other review findings deferred.

## Follow-up after Windows restart — 2026-10-18

- User confirmed restart and explicitly requested PostgreSQL software on Windows. Continue the existing foundation plan; do not redesign the Flutter app.
- Ruling: install the official PostgreSQL 17 server, command-line tools and pgAdmin on Windows, with a dedicated application role and UTF8 databases. Native services become the local development path; Compose remains available separately.
- Windows feature inspection reports VMP/WSL/Hyper-V Enabled, but vmcompute/HNS services and binaries are absent. Docker still fails its preconditions; DISM restore and SFC verification are running. Do not attribute this to BIOS without evidence.
- Ruling: use Memurai Developer for local Redis-compatible queue integration while Windows virtualization is repaired. It is not licensed for production and stops after 10 days; Docker Redis remains the deployment target. No inbound firewall exception was added; bind only 127.0.0.1.
- Native PostgreSQL17.11 installed successfully (verified installer SHA256 and EDB signature), psql/pgAdmin present, automatic service running with loopback-only listen addresses. Application role has no superuser/CREATEDB/CREATEROLE. Both UTF8 databases and migrations ready, seed32 products/256SKUs.
- pgAdmin server registration imported and bundled driver connection verified against32 products. Credentials kept in ignored private files; passfile ACL restricted to owner/admin/SYSTEM.
- DISM RestoreHealth exit0; SFC exit1 explicitly reports pending system repair requiring another restart. vmcompute/HNS still absent. Ruling: do not force another restart; native backend and queue are usable now, Docker runtime remains unverified.
- Unit namespace validation RED→GREEN. First queue integration attempt revealed ConfigModule snapshots env during import; tests now explicitly override validated ConfigService and use UUID queue prefixes. Removed only the five synthetic jobs/events from the initial default queue.
- Provider error regression RED→GREEN: raw provider message was persisted in Redis failedReason; worker now throws sanitized Error/UnrecoverableError. Retry count and unrecoverable behavior preserved.
- Verification: build/lint passed; unit5 passed; PostgreSQL17.11 commerce10 + Memurai worker6 passed. Worker tests cover disabled provider, retry3, sanitized failure, expired/deleted input, replay idempotency and ownership. HTTP tests cover missing/false consent.
- Native API/worker started; readiness200 with database=true/redis=true, Swagger200, catalog32. Compose config valid; host mappings5433/6380 avoid native5432/6379 conflicts.
- Flutter live catalog test passed against native PostgreSQL17 API. Full frontend source unchanged in this continuation; prior180-test/analyze/web-build evidence remains recorded separately.
- Queue-prefix compatibility documented: an installation that previously had BullMQ jobs under bull must retain AI_QUEUE_PREFIX=bull until drained; this user's old worker never ran real jobs.
- Fresh review fallback (first model at capacity): no Critical/Important production findings. Addressed three test reliability findings: explicit provider state (isolated replay test RED→GREEN), wait for actual outbox republication, database advisory lock plus unfinished-fixture preflight. Negative overlap check confirms refusal before inserting jobs.
- Review boundaries: host installation verified independently by service/driver/DB/readiness commands; real AI/storage/payment and Docker runtime remain outside the completed native scope; unchanged frontend/commerce retain prior evidence plus current E2E/live checks.
- Final post-review verification: isolated replay1 passed, overlapping-suite guard passed without mutation, full E2E16 passed, unit5 passed, lint passed. All three test findings addressed; no deferred minor findings in this continuation.
