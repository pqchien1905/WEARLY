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

## Private-image continuation — 2026-10-18

- Plan: docs/superpowers/plans/2026-10-18-private-images.md; base e29f846. Reattached master prompt is byte-identical to the original. User requested continuation, with installation/Git authority retained.
- Pre-flight: Task1 storage normalization feeds Task2 uploads and Task3 provider results; Task2 image deletion markers/lock feed Task3 cleanup/publication. New metadata columns nullable for existing fixtures; keys remain deterministic.
- Ruling: continue inline in the authorized checkout and preserve Flutter UI/mock mode — existing work and user intent — no isolated concurrent implementation in this directory.
- Ruling: use pinned official MinIO Windows binary for local development only after hash verification — legacy download URL now410 and official repo archived — production storage still needs a maintained deployment choice.
- Ruling: defaults8MiB/16MP,20 retained images,100 uploads/day,24h retention and20 AI jobs/image bound storage/cleanup — business policy not provided — these limits may need product adjustment before launch.
- Ruling: add S3_PUBLIC_ENDPOINT separate from internal S3_ENDPOINT — Compose minio hostname cannot be used by browsers — production must supply reachable HTTPS/DNS.
- Task1: image-policy tests observed3 failures before implementation, then3 passed; unit9 now passes including public signing endpoint RED→GREEN. Sharp decode/reencode removes EXIF/ICC, validates MIME/magic/dimensions. Real MinIO private buckets created and anonymous403/signed200/write/delete verified by E2E.
- Task2:4 initial upload E2E failed on missing routes, then passed. Additive third migration applied to native main/test, existing main catalog32 products/256SKUs preserved. Ownership/consent/format/size/storage failure/quota concurrency tested.
- Task3: purge retry and publication/delete race each observed failure then passed. Tombstones committed before S3 purge, deterministic result keys included, purgedAt only after success, timer retries every60s. Terminal jobs cannot be reset by late errors.
- Verification before review: build/lint passed, unit9 passed, E2E25 passed (commerce10, worker9, upload6). New tests use synthetic images, real PostgreSQL/Memurai/MinIO with isolated test bucket; paid AI remains a double/Disabled in the app.
- Final review: three Important lifecycle issues plus PNG structural validation discrepancy. Re-graded PNG as required input validation; fixed all four in one pass. Each regression observed RED then GREEN: result-sign/delete serialization; cleanup fairness after50 failing objects; resumed upload after purge; PNG terminator/trailing/CRC validation.
- Final: Ruling: unsupported bucket versioning/Object Lock remains excluded — cleanup deletes current objects only — enabling those features can retain historical bytes and requires a separate implementation.
- Final: Ruling: distributed throttling/commercial quotas remain deployment/product work — current single-process limits are explicit — scaling without distributed limits would weaken rate enforcement.
- Final: Ruling: provider quality/billing/external connectivity remain excluded while Disabled — no paid or fabricated AI claim — real provider acceptance still required.
- Final: Ruling: host/runtime evaluated separately — PostgreSQL/Memurai Running on loopback, MinIO private buckets, bounded compiled API and live Flutter catalog verified — persistent API/worker reload and Docker still not verified.
- Final: Ruling: production storage vendor suitability remains outside local MinIO setup — archived pinned binary only for development — deploying it unchanged would need separate security/maintenance evaluation.
- Final verification: build/lint pass; unit11 pass; E2E27 pass (commerce10/worker10/upload7); compiled API smoke readiness/catalog200, protected upload401 and OpenAPI routes present; Flutter live catalog1 pass. Main catalog counts unchanged32/256. Production npm audit0 known vulnerabilities. Four migrations applied to native main/test.
- Runtime limitation: automatic execution review rejected both stop/restart of known old API/worker PIDs and a new persistent API on3001 with only "blocked by policy". No process was stopped/started by those rejected calls. Bounded compiled smoke succeeded and closed its own app. Existing long-running API/worker remain the previous version; user reload instructions recorded in setup.md. No permission was requested again for already-authorized work.
- Integration: implementation commit cc32acc pushed to origin/main; ls-remote matched cc32acc64d6f3c9fa5756cf0db4a61c864480d56. Staged48 files passed a local secret-value scan; no frontend changes, .env files or local runtime data committed. Four migrations preserve main counts32 products/256SKUs/0 users/0 orders. Closing documentation is a separate commit; no further code changes after green verification.

## Docker recovery after confirmed restart — 2026-10-18

- User explicitly confirmed saved work and authorized restart after60s. Windows rebooted at20:39:14+07:00, after the DISM repair completed at19:18:42; previous boot was19:01:38.
- Fresh checks: VirtualMachinePlatform/WSL installed, hypervisor detected, vmcompute/hns binaries present and services Running, WslService Running, CBS RebootPending=false. `wsl --status` no longer reports virtualization failure.
- Started Docker with `docker desktop start --detach`. Desktop4.95.0, Engine29.8.2 Linux/amd64 Running; docker-desktop distro Running under WSL2. `docker run --rm hello-world` pulled the image and completed exit0.
- `docker compose up -d --wait postgres redis` succeeded. Both Healthy; PostgreSQL17.11 query succeeded; Redis PONG. Host binds127.0.0.1:5433/6380, native PostgreSQL/Memurai still Running at5432/6379. No native database/env changes, Docker reset, volume deletion or WSL unregister.
- Boundary: Docker DB newly created, not migrated/seeded; API/worker/MinIO container builds remain unverified. Native API/worker/MinIO dev processes ended during reboot and can be relaunched using setup.md. Only documentation changed in the repository for this repair; no application tests repeated for documentation-only edits.
