# Local foundation implementation plan

> **For agentic workers:** Use `executing-plans` inline, with a fresh review at the end of this milestone.

**Goal:** Repair native local time, schema readiness and migration/setup without losing business data; this is milestone one of the full local completion objective.

**Architecture:** Keep the existing modular monolith. Set UTC on every application pool connection, inspect required schema before reporting ready, and apply additive migrations after a verified backup.

**Tech Stack:** NestJS 11, Prisma 7, PostgreSQL 17, Node 24, Flutter.

**Spec:** `docs/superpowers/specs/2026-10-21-local-completion-design.md`

## Global constraints

- No business reset or seed overwrite. Preserve secrets and existing environment files.
- Database tests require a separate `_test` database. Real user data never enters logs.
- No external email, real payment or shipment. Existing inventory/transaction safeguards remain.

## Review focus

- A connection URL explicitly requesting a non-UTC timezone must not bypass the application's UTC contract (Task 1).
- Pool expansion must preserve UTC, not just the first connection (Task 1).
- Schema missing a new table or column must fail readiness without leaking schema details (Task 2).
- A dead DB/Redis must return bounded unavailability (Task 2).
- Updating a stale test endpoint must be explicit and preserve the previous configuration (Task 3).

## Task 1: UTC persistence and pool behavior

Files: `backend/src/database/prisma.service.ts`, new database timezone helper if needed,
`backend/test/database.e2e-spec.ts`, existing recovery E2E.

Produces: all PrismaService connections use UTC; databaseNow returns the real instant.

- [x] Add real PostgreSQL regression: requested Asia/Bangkok connection, compare databaseNow with Date.now within 2 seconds; assert new persisted timestamp matches the real instant and concurrent pooled connections report UTC.
- [x] Run database and recovery tests; observe current 7-hour failures.
- [x] Normalize connection configuration to UTC without changing the database server's timezone or user data.
- [x] Verify database/regression and full backend suites, lint/build; commit.

## Task 2: Schema-aware readiness

Files: `backend/src/database/schema-readiness.ts`, health controller,
`backend/test/database.e2e-spec.ts`, `backend/test/health.e2e-spec.ts`.

Consumes: real UTC PrismaService. Produces: `databaseSchemaReady(db): Promise<boolean>`
checks required model columns/types using generated schema and catalog metadata;
`GET /health/ready` returns 503 on incompatibility without exposing DB details.

- [x] Add real-schema tests for complete schema and missing required table/column;
  endpoint tests distinguish liveness from unavailable readiness.
- [x] Observe red, implement metadata check and bounded dependency probes.
- [x] Verify success and failure paths against real PG/Redis; lint/build/full suites; commit.

## Task 3: Native setup and migration

Files: test helpers as required, `docs/setup.md`, `README.md`, completion ledger.

- [x] Reproduce the stale 5433 test endpoint and preserve its configuration as a backup.
- [x] Verify dedicated 5432 test setup; fix Windows nested-worktree test discovery if required.
- [x] Create a custom-format pg_dump of local business DB; inspect archive contents.
- [x] Apply additive migrations to business DB, compare business-table counts and values, verify auth/content/admin/catalog reads and ready status.
- [x] Restore into a distinct test destination/schema when feasible without modifying the source; record evidence and any remaining restore gate.
- [x] Update README/setup and verification ledger, independent milestone review, commit.

## Next milestones (full scope retained)

- Shipping persistence, COD settlement and commercial reporting.
- VNPay sandbox, promotions, shipment tracking, cancellation/return/refund.
- Local email/support, role permissions and persistent sessions.
- Gemini Stylist/try-on and their real frontend flows.
- CI, local monitoring/backup, store content/SEO and end-to-end acceptance.

Each receives a detailed plan before implementation; none is completed by this foundation milestone.
