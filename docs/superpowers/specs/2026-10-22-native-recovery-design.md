# Native local backup and recovery

Continuation of outcome9 in `2026-10-21-local-completion-design.md`. The user
authorized completion of the local shop; retain native PostgreSQL17, Redis,
MinIO and the existing business data. No production deployment, service restart,
overwrite, database drop, volume reset or automatic cutover.

## Operator outcome

An executable Windows command backs up the configured local business database
and managed catalog images into a new private local archive. Another command
verifies that archive and restores it to a newly named, retained database and
private bucket. A report proves the original snapshot's data/schema and image
checksums survived, then explicitly records the recovery quarantine changes.
The source database, bucket, services, code and `.env` remain untouched.

The backup is useful for recovering local commerce records, not a promise of
off-host disaster recovery. Backups contain customer records and password hashes:
keep them private, outside Git. No provider keys or environment files are copied.
Manual backup means recovery can lose work after the chosen snapshot; report
snapshot time and duration. Never silently delete older archives or failed targets.

## Consistency and archive contract

- Validate loopback PostgreSQL and S3 endpoints and non-production mode before
  connecting or writing. The source may be the configured business DB; restore
  targets must be freshly generated `wearly_recovery_<time>_<uuid8>` names and a
  distinct `wearly-recovery-<time>-<uuid8>` bucket. Operators cannot select an
  existing destination. Use admin credentials only to create that database;
  restore as its ordinary app owner, never as a PostgreSQL superuser.
- Use a read-only REPEATABLE READ transaction and `pg_export_snapshot()` so
  table fingerprints, catalog asset selection and `pg_dump --snapshot` refer to
  one database state. Stream ordered canonical row fingerprints with bounded
  reads; do not serialize customer rows into the report. Record table counts,
  schema definitions, migration state and hashes. Use native PostgreSQL17 tools,
  custom-format dump and bounded child-process exit/error handling.
- Copy only immutable verified, nondeleted, nonpurged CatalogAsset objects;
  verify declared size and SHA256. If a needed object is missing, changes or is
  too large, the backup fails and cannot be restored as a successful archive.
  Snapshot consistency does not freeze S3: fail honestly instead of certifying
  a database backup whose required pictures disappeared during collection.
- Also retain the bundled `frontend/assets/images` files and hashes under the
  archive. They are code assets, not S3 objects; never overwrite the workspace
  during restore. Record source Git revision and require matching bundled assets
  for any compiled-app verification. External URLs are not fetched or promised
  backed up. Unknown catalog URL forms are reported as exclusions.
- Fresh archive directory only, canonical contained paths, reject nested links
  and traversal. Protect Windows directory ACL for current user and SYSTEM before
  writing sensitive content. No plaintext credentials in argv/logs/reports. Hash
  every file, validate manifest before network mutation, and publish success only
  after all files and checks complete. Hashes detect corruption, not malicious
  modification by the same Windows account; only restore this tool's trusted
  local archives.

## Restoration and quarantine

Create fresh targets after the complete archive validates; refuse collisions.
Use `pg_restore --exit-on-error --single-transaction --no-owner --no-privileges`,
without `--clean` or `--create`. Verify restored schema and every table fingerprint
against the snapshot before any deliberate transformations. Upload validated
catalog bytes to the new private, unversioned bucket and verify them again. Keep
both successful and failed targets for inspection; no automatic deletion.

Before the restored application can be inspected, perform one explicit quarantine
transaction on the destination only:

- Revoke all refresh/browser sessions and consume recovery tokens. Disable
  restored accounts until the operator verifies ownership and assigns a fresh
  password; this avoids resurrecting a previously changed password or staff role.
  Preserve original roles and commerce relations as historical data. A restore
  drill does not automatically activate any administrator.
- Do not back up or restore private uploaded Try-On photos or generated results.
  Tombstone/expire restored ImageAsset and TryOnResult metadata. Preserve job and
  quota history, but mark pending/processing AI jobs failed and unsettled usage
  UNKNOWN with an explicit local-recovery reason. Publish/suppress pending AI
  outbox rows so enabling a worker cannot resubmit an old paid request.
- Suppress pending/processing MailOutbox entries with an explicit recovery reason
  and clear leases. Keep sent mail history. No Redis queues/session caches are
  restored; give the inspection environment a fresh queue namespace.
- Keep order/payment/refund/settlement history and amounts unchanged. Do not infer
  payment success, refund money or recreate shipments. Provider credentials,
  external mail and VNPay remain disabled in generated inspection configuration;
  uncertain historical transactions need operator reconciliation before reuse.

The report distinguishes exact restoration from these expected changes. Verify
all other tables remain identical and every affected table satisfies the specified
transformations. Generated inspection environment lives privately in the recovery
directory with new JWT secrets and the new DB/bucket/queue; never replaces normal
backend/.env, never starts a worker and never changes the active store.

## Acceptance

First use a dedicated synthetic test source containing a managed picture, active
session/reset token, private photo metadata, pending AI work and pending mail.
Prove exact round-trip then quarantine, old-auth refusal, no external requests,
missing/corrupt files rejected before target creation, collision refusal and
source fingerprints unchanged. Verify compiled API readiness/catalog and served
catalog bytes against the restored target, without starting a worker.

Then back up the real local business database read-only and restore into fresh
retained targets using the same implementation. Record counts/checksums and source
preservation, not private row data. Synthetic tests alone do not satisfy this gate.
No Mailpit restart, Redis flush or service teardown is part of recovery.

## Implementation choices and references

These are builder choices under the existing A-Z/local authorization: fail a
backup when a required object is unavailable; exclude ephemeral private photos;
quarantine restored accounts/work; retain targets without cutover. They trade
one-click activation for preserving privacy and preventing replay. The operator
guide must explain how to inspect retained data and the checks needed before
manually reactivating a restored shop.

Primary documentation checked22October2026:
[pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html),
[pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html),
[snapshot synchronization](https://www.postgresql.org/docs/17/functions-admin.html#FUNCTIONS-SNAPSHOT-SYNCHRONIZATION).
