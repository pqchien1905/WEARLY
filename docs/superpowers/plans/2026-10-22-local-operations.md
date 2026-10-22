# Local operations implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, inline. One independent final reviewer, no implementer agents.

**Goal:** Give the local operator useful diagnostics, owned process lifecycle and repeatable CI checks without modifying existing business data or external services.

**Architecture:** Bounded independent probes feed an ADMIN-only read model and Flutter operations page. A Redis heartbeat records worker liveness. Native Node/PowerShell helpers manage authenticated loopback children; CI uses synthetic services. Backup/restore is a separate required milestone, not omitted.

**Tech Stack:** Existing Node24/NestJS11/Prisma7, Flutter3.47.7/Riverpod, PostgreSQL17, Redis/BullMQ, MinIO, PowerShell5.1 and Node test runner.

**Spec:** docs/superpowers/specs/2026-10-22-local-operations-design.md; parent docs/superpowers/specs/2026-10-21-local-completion-design.md, outcomes1/9.

## Global constraints

- Local only; no external Gemini/VNPay/GHN calls, physical shipments or charges.
- Keep existing services and root.env values; all secrets stay in backend/env or
  ignored private runtime state, never Flutter/public diagnostics/log messages.
- No reset, seed overwrite, blind time shift or unbacked migration. No schema
  change is expected in this milestone. Native business26 remains intact.
- Synthetic integration tests use *_test DB, -test bucket and UUID queue prefixes;
  serialize actual worker suites with existing advisory lock. Never FLUSHDB.
- Do not build/generate/change backend during full E2E. Flutter runs sequentially.
- Existing Mailpit restart auto-review rejection remains an explicit limitation;
  no stop/restart workaround. API/worker/web children have a separate owned lifecycle.
- One independent review of this whole milestone, one tested fix pass, no re-review.

## Decisions and contracts

- GET /api/v1/admin/operations, @Admin('staff.manage'), private,no-store. Response
  `{observedAt, database, redis, storage, worker, mail, providers, work}`. Sections
  have status ok/unavailable/disabled; absent measurements are null, never invented0.
- Database probe uses its own pg transport with UTC, connect500ms/query1500ms/
  statement1000ms and hard2s deadline/destroy. Reports schemaReady, migrations count,
  pending outbox/oldest age, active/stale AI usage, failures by sanitized code/kind
  over24h, today UTC count/estimatedVND, mail pending/failed and image cleanup backlog.
  It returns only aggregate data; no account/job IDs, private rows or SQL details.
- Redis probe is independent, connect/command1000ms, no offline queue/retries;
  fetch exact configured namespace queue counts (waiting,active,delayed,failed)
  for AI and enabled password-recovery, with oldest waiting age where available.
  Dispose Queue/Redis resources under deadline. No job payload/stacktrace reads.
- S3 uses authenticated HeadBucket,2s abort,maxAttempts1; no bucket policy change.
  Local mail probe checks configured SMTP socket when enabled,1s, then destroys.
- WorkerHeartbeat writes `{instanceId,startedAt,lastAt}` at startup/every10s to
  `<AI_QUEUE_PREFIX>:monitor:worker`, TTL30s. Graceful stop clears only its own value
  using compare-and-delete; a stale worker cannot remove another instance's value.
  Read model calls it live only within30s. Liveness is explicitly separate from
  queue progress; heartbeat failure logs a sanitized code, not Redis credentials.
- UI reuses /admin/ai-monitoring, labelled “Vận hành & AI” in remote navigation.
  ADMIN only; demo unchanged. Manual refresh; preserve account-scoped late-response
  guards. Show counts, UTC reporting window, estimated cost and useful local next
  steps. No internal stacktraces or buttons that blindly retry paid jobs.
- tools/local.ps1 build|start|status|stop delegates Node runtime helpers. Build
  checks native exit codes and compiles API/Flutter web with localhost API URL.
  Start refuses missing build, incompatible local configuration, unavailable
  dependencies or occupied unmanaged ports; never seeds/migrates or kills a port.
- Each API/worker/web child owns an authenticated loopback control listener and
  private state containing workspace identity, run nonce, pid and control address.
  Commands authenticate that identity, not just PID. Stop asks the child to close
  Nest/server resources; bounded grace150s for AI work. Startup failure cleans up
  only children created by that same attempt. Hidden background processes on Windows.
- Runtime uses canonical workspace-scoped state under ignored .tools/runtime;
  realpath/path-containment checks protect any state/log mutation. No recursive
  deletion. Bounded rotating local logs, no environment dumps. Control secrets are
  never command-line arguments. Read-only status must not start anything.
- API bind address becomes validated HOST, default127.0.0.1; Compose explicitly
  supplies0.0.0.0 to preserve its mapped container behavior. Runtime always loopback.
- CI workflow uses Ubuntu service containers for Postgres17/Redis7 and local MinIO,
  Node24 and locked dependencies. Flutter pinned3.47.7. Read-only checkout permission;
  no real secrets/provider credentials. CI environment helper refuses non-test DB
  or existing user.env overwrite. Report local checks vs hosted execution honestly.

## Review focus

1. Stale process state/PID reuse/occupied port: status/stop never controls another
   program, and a partial startup cleans up only this attempt's authenticated children.
2. A dependency accepts a connection but never replies: probes time out and destroy
   resources; operations page reports unavailable instead of green/zero or hanging.
3. Worker is alive but work is stuck, or Redis disappears: liveness never certifies
   job success; backlog age/failure summaries remain honest and private.
4. Account changes while diagnostics are loading: no admin details cross into a
   customer/other staff session, including refresh and mobile navigation.
5. CI/runtime configuration accidentally points at business resources or enables
   external providers: guards stop before writes/calls; credentials stay out of logs.

## Task 1: bounded operations read model and worker heartbeat

Files: create backend/src/modules/operations/{operations.module,operations.controller,
operations.service,operations.probes,worker-heartbeat.service}.ts; modify app.module,
worker/worker.module; test/operations.spec.ts and operations.e2e-spec.ts.

Interfaces: OperationsService.snapshot():Promise<OperationsSnapshot> from independent
OperationsProbes.database()/redis()/storage()/mail(); WorkerHeartbeat lifecycle uses
configured prefix and injectable bounded Redis transport. No Prisma migration.

- [x] Write RED for admin-only access/no-store, aggregate fixture counts and no PII,
  missing/stale/foreign heartbeat, compare-and-delete, disabled integrations,
  unresponsive PG/Redis/S3/SMTP and honest partial failure. Expected missing module.
- [x] Implement probes/DTO/read model, heartbeat and module wiring. Bounded clock/
  injection seams support unit tests; real PG/Redis route tests prove authorization
  and namespace isolation. Do not log raw provider/DB errors.
- [x] Run focused Jest, then full native E2E with worker/storage and unit/lint/build;
  inspect results and commit. No business data mutation.

## Task 2: remote admin operations view and browser acceptance

Files: frontend/lib/data/remote_operations.dart;features/admin/remote/operations_page.dart;
admin_shell.dart,remote/admin_pages.dart;test/remote_operations_test.dart;
tools/test-frontend-api.cjs --operations;tools/verify-operations-browser.cjs.

Interfaces: Task1 OperationsSnapshot; existing adminApiClientProvider, AdminAsync,
staff.manage route permissions and account-keyed RemoteAdminRoute lifecycle.

- [x] RED DTO/widget tests: unknown vs zero, stale worker with pending queue,
  disabled provider/mail, exact estimates, retry, changed account/late data and375px.
- [x] Implement navigation/page in existing design system. No paid retries and
  no settings secret editors. Fixture browser uses real PG/Redis and synthetic
  aggregate state, verifies ADMIN access and other-role denial at375/1440.
- [x] Focused/full Flutter/analyze and Chrome PASS; inspect screenshots, commit.

## Task 3: owned native API/worker/web lifecycle

Files: tools/local.ps1,tools/local-runtime.cjs,tools/local-runtime-child.cjs,
tools/local-runtime.test.cjs,tools/verify-local-runtime.cjs; refactor tools/serve.cjs
to expose a safe static server factory while preserving preview defaults; backend
config/env.validation.ts,.env.example,main.ts;docker-compose.yml HOST overrides.

Interfaces: runtime build/start/status/stop accept workspace/ports in validated local
config; child control GET status/POST stop requires per-run secret +workspace/role
identity. Parent receives only health/state/exit results, not environment contents.

- [x] RED tests for stale/forged state, PID reuse, foreign port, path escape,
  startup rollback, failed health, zero writes on status and nonzero native exit.
- [x] Implement hidden children with control authentication, bounded start/stop,
  log containment/rotation and matching local CORS/recovery origin. Existing native
  services are prerequisites, not stop targets. Build never migrates or seeds.
- [x] Verify real start/status/stop on isolated test DB/prefix/ports; test worker
  heartbeat and API readiness plus static web. Keep normal services untouched.
  Run relevant backend/tool/Flutter checks; commit.

## Task 4: CI, operator guide and final milestone review

Files: .github/workflows/verify.yml,tools/ci-verify.cjs,tools/ci-verify.test.cjs,
tools/acceptance.ps1,docs/LOCAL_OPERATIONS.md,README.md,docs/setup.md,
docs/LOCAL_COMPLETION_PROGRESS.md.

- [ ] RED environment/command guards; implement locked synthetic CI and serial
  local acceptance profiles using existing domain-specific browser helpers.
  CI does not overwrite.env, seed business data or obtain real provider keys.
- [ ] Run local workflow commands and YAML/guard checks. Update operator docs with
  current login persistence, Gemini/VNPay status, runtime commands and monitored
  failure handling; distinguish prepared hosted workflow from an observed hosted run.
- [ ] One independent whole-milestone reviewer, regrade findings, one tested fix
  pass, relevant final suites and compiled local smoke. No re-review loop.
- [ ] Commit final evidence/checklist, remove only this plan's scratch. Goal stays
  active for native backup/restore, identity/policies/SEO, configured providers and
  final integration into D:/Fashion Shop.

Primary CI references checked22Oct2026: https://github.com/actions/checkout and
https://github.com/actions/setup-node currently document v7; Linux service-container
requirement: https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers .
Installed Flutter cache identifies3.47.7/Dart3.13.5; no toolchain upgrade required.

Self-review: parent outcome9 is split at independently verifiable runtime/monitoring
and recovery boundaries. Backup/restore remains required. No branch integration at
this intermediate milestone; no implied production/provider acceptance.
