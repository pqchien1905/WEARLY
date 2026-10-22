# Native recovery implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline. One final independent review, no implementer agents.

**Goal:** Back up native local commerce data and catalog images and prove recovery into fresh retained targets without reactivating old credentials or pending side effects.

**Architecture:** Guarded Node/PowerShell commands orchestrate a PostgreSQL exported snapshot, custom archive, verified object copies and manifest. Restore validates all artifacts before fresh target creation, proves exact data/schema equivalence, then quarantines sessions/private photos/pending work. Acceptance first uses synthetic fixtures, then the actual local business snapshot read-only.

**Tech stack:** Node24, native PostgreSQL17 tools/client, existing pg/AWS SDK/dotenv dependencies, MinIO and Windows PowerShell5.1.

**Spec:** docs/superpowers/specs/2026-10-22-native-recovery-design.md; parent local-completion outcome9.

## Global constraints

- Local only, nonproduction, no external providers. No DROP/TRUNCATE/reset/seed,
  source mutation, overwrite, service restart, Redis flush or automatic cutover.
- Native business/test schema26; no schema migration in this milestone.
- Canonical contained private archive paths. Existing .tools junction is accepted
  only through the same Git-worktree ownership rule as local-runtime. No nested
  symlinks or archive paths supplied by unchecked metadata. No recursive deletion.
- Retain every archive and new destination, including failures. No success manifest
  until every required file/hash/object/database check passes. Fail closed on limits.
- Backup source connection is the ordinary configured application role; a separate
  local admin credential file supplies CREATE DATABASE only. pg_restore connects
  as app owner. Never print credentials, raw rows, request bodies or native stderr.
- Read native credentials privately from existing `.tools/postgres-admin.json` when
  needed; do not copy that file into an archive or alter it.
- Synthetic source uses dedicated `_test` database/`-test` bucket/UUID fixtures,
  serialized worker-suite advisory lock. Never start a worker on restored data.
- Execute inline with TDD and one final fresh review. Existing A-Z authorization
  covers these reversible fresh-target operations; no repeated design approval.

## Review focus

1. Source data changes during a backup or an image vanishes: one exported database
   snapshot is used everywhere, and missing required bytes cannot yield success.
2. Corrupt manifest/hash/path or reused target: no writes to network resources
   occur before validation, and an existing DB/bucket is never overwritten.
3. Restore revives old sessions/reset tokens/photos or accepted side effects:
   exact-restore verification is followed by explicit quarantine before API use.
4. Partial failure or interrupted native command: retained reports say failed or
   incomplete; no source deletion, secrets in errors or misleading completion.
5. Current workspace assets/schema differ from the archive: restoration preserves
   the old data, but app compatibility is reported honestly rather than silently
   copying code/assets over the working directory.

## Task 1: consistent native backup

Files: tools/native-recovery.cjs (configuration/path/manifest/CLI orchestration),
tools/recovery-postgres.cjs (snapshot/native tool I/O), tools/recovery-objects.cjs
(catalog/bundled files), tools/native-recovery.test.cjs,tools/recovery.ps1.

Interfaces:
- `backup(workspace, options)` returns private archive path and aggregate evidence.
  CLI `node tools/native-recovery.cjs backup --env-file backend/.env`.
- `validateConfig(env)` requires local postgres/S3 and nonproduction; returns
  parsed connection settings without logging. `locations(workspace)` uses a fresh
  `.tools/recovery/<workspaceHash>/<timestamp-uuid>/` directory per backup.
- `snapshot(client)` returns table counts/ordered SHA256 plus columns/enums/
  constraints/indexes/triggers/functions, with schema-qualified queries, UTC and
  stable C ordering. Read rows in batches500 via cursor inside caller transaction.
- `collectObjects(client,s3,directory)` selects verified active CatalogAsset rows
  from that snapshot, validates key/id/mime/size/hash, copies each with 8MiB limit,
  10s request deadline and maxAttempts1. Bundled assets are copied with realpath
  containment. Aggregate max10000 files/1GiB; any limit failure is explicit.
- Manifest version1 records source DB name, schema snapshot, file sizes/hashes,
  object metadata, bundled-file metadata, Git revision, times and exclusions;
  never stores DB URL, credentials or row contents. Status starts incomplete,
  becomes complete only after dump TOC and every file verification pass.

- [x] Write guards/manifest tests: remote DB/S3, production, unsafe root/linked
  child, missing/corrupt object, exceeded bound, unexpected secret in errors.
  Run Node tests; Expected: missing helper/behavior RED before implementation.
- [x] Implement private directory protection before writes, native PostgreSQL17
  version checks, exported snapshot and bounded pg_dump -Fc --snapshot with
  credentials in environment only. Validate archive via pg_restore --list.
- [x] Test snapshot stability with a concurrent synthetic row change after export;
  dump/fingerprints must match the old snapshot. Missing image must retain an
  incomplete archive, never a complete one. Tests use fixtures, not business edits.
- [x] Run guards + synthetic backup acceptance; Expected: all pass, source data
  preserved, no existing files overwritten. Commit deliverable/evidence.

## Task 2: fresh restore and quarantine

Files: same helpers/tests; tools/verify-native-recovery.cjs (synthetic acceptance).

Interfaces:
- `restore(workspace, archive, options)` validates complete manifest and every file
  hash/path before any network mutation. CLI accepts only a contained archive.
- Generate target names `wearly_recovery_<time>_<uuid8>` and
  `wearly-recovery-<time>-<uuid8>`; record ownership intent before CREATE DATABASE
  /CreateBucket. Reject DB/bucket collision without modifying either resource.
- `quarantine(client)` uses one transaction: all User.active=false;
  RefreshToken.revokedAt/PasswordResetToken.consumedAt set if absent; all private
  ImageAsset.deletedAt/purgedAt and expiry set, TryOnResult expiry set; active
  AIJob ->FAILED/errorCode LOCAL_RECOVERY_REVIEW; active AiUsage ->UNKNOWN with
  finishedAt and LOCAL_RECOVERY_REVIEW; unpublished OutboxEvent marked published;
  pending/processing MailOutbox ->FAILED/lastError LOCAL_RECOVERY_REVIEW and clear
  leaseToken/leaseUntil. Preserve all unrelated columns and quota estimates.
- `verifyQuarantine(before,after)` proves exact allowed row transforms using the
  destination transaction, counts and fingerprints of untouched tables. No DELETE.
  Save aggregate evidence and inspection.env privately with new JWT secrets,
  disabled providers/mail, new DB/bucket/queue. Never load it into the live app.

- [ ] Write RED tests for target collision, corrupted dump/file, traversal, partial
  restore, old session/reset token and pending side effects; Expected: fail before
  implementation. Include an old active staff account and private image metadata.
- [ ] Implement restore as ordinary app user with single transaction/no-owner/
  no-privileges/no-clean/no-create. Compare exact snapshot before quarantine,
  create private unversioned target bucket, restore/get/hash every catalog object.
- [ ] Implement/test quarantine and private inspection configuration. Assert no
  active sessions/accounts/pending AI/mail remain, commerce amounts unchanged,
  no private photo bytes archived or restored. No worker start/network providers.
- [ ] Run synthetic API acceptance: readiness/catalog, managed image bytes, old
  bearer/session rejected. Verify source snapshot/objects unchanged and retain
  target/report. Expected: all pass; commit.

## Task 3: business recovery drill, operator guide and review

Files: docs/NATIVE_RECOVERY.md,docs/LOCAL_OPERATIONS.md,docs/setup.md,
README.md,docs/LOCAL_COMPLETION_PROGRESS.md; helpers as required by acceptance.

- [ ] Run the same backup against configured native business database read-only,
  then restore to fresh retained targets. Validate source counts/hashes unchanged,
  exact pre-quarantine target schema/data, post-quarantine expected differences,
  catalog byte verification and compiled API read-only readiness/catalog. Never
  register users, grant roles, start worker or activate restored business accounts.
- [ ] Document backup/restore commands, local private retention, manual RPO, source
  preservation, excluded private images/external URLs, exact vs quarantine evidence,
  no automatic cutover, account/password/operator reconciliation needed before any
  later activation. Document retained failure recovery without unsafe cleanup.
- [ ] Run all Node tool guards, relevant backend validation and compiled app smoke.
  Full backend/Flutter suites only if product code changes or a new concern warrants
  them; don't rerun unrelated suites to inflate evidence. Commit checkpoint.
- [ ] One fresh strongest-model reviewer of whole recovery milestone, with this
  Review focus verbatim and rulings. Regrade by user effect, one tested fix pass,
  no rereview. Record all exclusions/remaining limitations, commit final evidence,
  remove only this plan's scratch. A-Z goal remains active for identity/policies/SEO,
  configured-provider acceptance and final root integration.

Self-check: database snapshot and object manifest share the exporting transaction;
restore consumes complete manifest only; exact verification precedes quarantine;
inspection config never changes the live store. Business backup is intentionally
permitted only for read-only source access, while all restore mutation targets are
fresh generated resources. No production backup or live-provider claim follows.
