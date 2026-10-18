# Private image lifecycle implementation plan

> **For agentic workers:** Use executing-plans inline. This continues the user's authorized Wearly master prompt; preserve Flutter and existing commerce behavior.

**Goal:** Implement authenticated private uploads, owned reads/deletion and durable expiration cleanup, and connect these guarantees to the AI worker.

**Architecture:** NestJS UploadsModule and S3 adapter; PostgreSQL stores metadata and durable deletion markers, never image bytes. A maintenance task in the existing separate worker purges expired/deleted objects. The AI provider remains disabled until a real adapter is supplied.

**Tech Stack:** Existing NestJS11/Prisma7/PostgreSQL17/BullMQ, Sharp for decoded image validation and metadata stripping, native MinIO for local S3 verification.

**Spec:** User master prompt reattached 2026-10-18, sections 3, 9, 10; docs/migration-plan.md private-upload gap.

## Global constraints and decisions

- Work in the existing authorized checkout; preserve UI, mocks, existing services and data. Additive migrations only.
- Accept one JPEG/PNG of at most8MiB, at most16 million pixels and dimensions64..8192; decode and re-encode to remove EXIF and reject corrupt/polyglot content. Do not trust filename or MIME alone.
- Explicit multipart consent=true, rate limit uploads,20 non-purged images and100 uploads/day/user,24h retention. These are conservative local defaults chosen by the implementer and documented.
- GET/read/delete always enforce ownership. Signed reads expire in60s; previously issued URLs may remain usable until expiry or object purge. No public bucket/anonymous access.
- Persist a metadata reservation before S3 upload; failed uploads become tombstones for retry cleanup. Mark verified only after storage succeeds.
- Deletion immediately revokes application access and cancels pending/processing jobs; physical purge is asynchronous, retried by the worker. Store purgedAt only after S3 deletion succeeds.
- Serialize worker result publication and deletion with a per-image advisory transaction lock. S3 calls have bounded network timeouts; cleanup uses deterministic job result keys as well as persisted results.
- No real AI/payment success claims. Native MinIO is local development infrastructure; Docker still depends on pending Windows repair.

## Review focus

1. Forged MIME, malformed/truncated image, EXIF GPS and decompression bomb must not enter storage.
2. An owner must not read/delete another owner's image or regain access after deletion/expiry.
3. S3 outage/crash between upload and metadata update must leave inspectable retryable cleanup state.
4. Image deletion while generation/storage is in progress must not republish a usable result.
5. Expiration/cleanup retries must not erase unrelated objects or mark a partial purge complete.

## Task 1: Image policy and S3 primitives

Files: backend/src/integrations/storage/{image-policy,storage.service,storage.module}.ts; backend/test/image-policy.spec.ts; backend/package*.json.

- [x] Write image-policy tests and observe rejection failures for missing behavior.
- [x] Implement strict decode/re-encode, bounded images and metadata stripping; add Sharp and typed multipart dependency.
- [x] Add bounded S3 read/write/delete primitives, shared StorageModule and local private MinIO setup.
- [x] Run unit/build and real S3 write/read/delete smoke.

## Task 2: Owned upload lifecycle

Files: backend/prisma/schema.prisma, additive migration; backend/src/modules/uploads/*; backend/test/uploads.e2e-spec.ts; app.module.ts.

- [x] Write authenticated upload/ownership/deletion/limits/storage-failure E2E tests and observe missing-route failures.
- [x] Implement metadata reservation, quota transaction, uploaded-byte validation, consent, signed reads and deletion tombstones.
- [x] Apply migration to existing native main/test DBs, verify no prior rows removed.
- [x] Run real PostgreSQL + MinIO E2E with a dedicated test bucket.

## Task 3: Retention and AI result race safety

Files: modules/uploads/image-lifecycle.service.ts; worker/{retention.worker,ai.processor,worker.module}.ts; common/transaction.ts; worker E2E.

- [x] Add regressions for deletion vs generation, expired/pending upload cleanup, failed S3 purge retry and completed-job idempotency.
- [x] Implement durable cleanup and image-lock publication; never overwrite terminal job states.
- [x] Run unit, commerce, worker and uploads E2E, build/lint, live Flutter catalog.
- [ ] Update API/schema/architecture/setup/report/ledger, fresh read-only final review, fix findings, commit and push.
