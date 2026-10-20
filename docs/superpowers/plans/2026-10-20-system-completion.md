# System Completion Implementation Plan

> **For agentic workers:** Use executing-plans for native execution, regression
> tests first, then a fresh review before integration.

**Goal:** Repair and verify the existing system against the attached objective.
**Architecture:** Preserve modular NestJS/PostgreSQL and Flutter remote adapters.
Isolate build/migration tooling from application runtime; keep real service tests.
**Tech Stack:** Node 24, NestJS 11, Prisma 7, PostgreSQL 17, Flutter, Redis, S3.
**Spec:** Attached `goal-objective.md`; findings in `docs/SYSTEM_AUDIT.md`.

## Constraints and review focus

No production deployment, destructive database operations, mock substitutions,
new business policies or secret disclosure. Verify malformed requests, missing
relations, cleanup failures, runtime dependency availability and existing checkout.
Track subsequent iterations in IMPLEMENTATION_PROGRESS.md.

## Task 1: HTTP and database errors

Files: backend/test/commerce.e2e-spec.ts, backend/test/admin.e2e-spec.ts,
backend/src/common/filters/api-exception.filter.ts.

- [x] Exercise malformed JSON (400) and body over parser limit (413) through HTTP.
- [x] Exercise missing category/brand/product UUIDs and gallery rollback with PostgreSQL.
- [x] Observe failing regression before mapping safe, non-retryable errors.
- [x] Run unit/lint/build and affected E2E; preserve unknown errors as generic 500.

## Task 2: Integration cleanup

File: backend/test/uploads.e2e-spec.ts.

- [x] Preserve the failed-storage baseline as reproduction.
- [x] Always close S3/Nest using finally, even if fixture cleanup throws.
- [x] Re-run storage E2E with unavailable storage and confirm bounded failure.
- [x] Start existing local storage and run complete 53+ E2E cases.

## Task 3: Deployable containers

Files: backend/Dockerfile, backend/Dockerfile.worker, docker-compose.yml,
tools/verify-containers.cjs, docs/setup.md.

- [x] Inspect current container verification and Prisma migration runtime needs.
- [x] Build production-only API/worker and a separate migration target.
- [x] Run migrations before API startup through the migration image.
- [x] Verify non-root API/worker, readiness, real COD flow and worker processing.

## Task 4: Continue completion

- [x] Assess remaining feature contracts from existing schema/UI.
- [ ] Implement locally verifiable missing features with focused plans/tests.
- [x] Run browser customer/admin flows at desktop and mobile sizes.
- [x] Run fresh security/build checks and independent review.
- [x] Publish evidence-based handoff, marking external gaps BLOCKED.

## Additional operational verification completed

- [x] Assert bootstrap fixture changes affect exactly one row.
- [x] Add test-only recovery guards, dump/copy/restore into a new DB, compare all
  data/schema/enum/index definitions; retain source/target/archive.
- [x] Read-only compiled API smoke against restored and regular local DB.
- [x] Repair preview URI crash and verify malformed/NUL 400 plus healthy homepage.
