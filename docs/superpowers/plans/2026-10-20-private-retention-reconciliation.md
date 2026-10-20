# Private image retention reconciliation

**Grounding:** image-lifecycle.service.ts returns early for any purgedAt and
excludes those rows from future sweeps. A remote PUT accepted before a lost
response can complete after the first DELETE, leaving private bytes behind.
Catalog cleanup already handles this failure mode.

**Scope:** Preserve current private API/consent/24-hour expiry, user quotas and
worker architecture. Revisit revoked/purged tombstones with the existing
purgeRetryAt field. No migration, provider integration or retention extension.

- [x] Reproduce against real PG/MinIO: failed upload reservation, initial purge,
  late remote object, due sweep, expected physical absence and continued404.
- [x] Remove terminal purgedAt exclusion; schedule successful reconciliation
  after24hours, failed retries after5minutes. Prioritize never-purged work and
  retain50-row batches. Always preserve live images and exclude not-yet-due
  work. Keep user quota based on initial successful purge.
- [x] Run targeted/private/worker/full regression, backend lint/build, review,
  rebuild affected runtime images and run container checks on fresh fixtures.
- [x] Update audit/progress/private-image docs with evidence.

Full80E2E and targeted8private tests passed, including no retry before due.
Runtime images passed fresh bootstrap/container verification; no schema change.
