# Catalog object recovery implementation plan

> Execute inline using executing-plans; keep existing business data untouched.

**Goal:** Prove that verified catalog objects can be exported and restored into
a new private local bucket, then served by the API using the restored database.

**Architecture:** Extend the existing retained bootstrap/container/DB-recovery
evidence chain with a separate guarded CLI. It accepts only a successful
synthetic handoff DB and matching restored DB report. Use the installed S3 SDK,
Prisma-generated runtime/StorageService and PostgreSQL client. No production,
business bucket writes, overwrites, deletes, policy changes or external services.

**Scope:** Verified nondeleted CatalogAsset objects referenced by the retained
synthetic DB, including removed-gallery assets. This does not certify private
Try-On object recovery, historical versions, roles/grants, off-host durability,
encryption/key recovery or production RPO/RTO.

- [x] Add `tools/verify-object-recovery.test.cjs`: reject mismatched/failed
  evidence, business names/buckets, production, remote endpoints, unsafe object
  keys, invalid sizes/MIME/hashes and corrupt local bytes.
- [x] Add `tools/verify-object-recovery.cjs`: bounded read-only DB snapshots;
  validate source/restore catalog metadata equality; require local test bucket
  with no public policy/versioning; export normalized bytes into a fresh
  ignored directory with manifest and hashes.
- [x] Restore the files into a new UUID-named bucket, retain it, and refuse
  existing destinations. Use conditional PUT to prevent overwriting keys.
  Check source unchanged, restored hash/MIME/size equal and anonymous403.
- [x] Start compiled API with restored DB/new bucket on ephemeral loopback port;
  GET catalog images and compare exact hashes. Always close API/clients/pools;
  retain partial evidence on failure and print only error classes/codes.
- [x] Run helper regressions and actual local recovery, independent review,
  then update setup/audit/progress/handoff with precise evidence and limits.

Review found Nest's default startup abort bypassing cleanup/reporting. Explicit
abortOnError:false and shared recording/finally handling fix it; a real failing
provider in a child process verifies the path. Resource construction is also
inside failure handling. Four new tests plus nine existing helper tests pass.
Final actual run: `objects-1792481707240-02dceafb`, source handoff directory.
