# Implementation progress — 20/10/2026

Goal: execute the attached system completion objective. Status: **IN PROGRESS**.

## Completed

- Read objective, repository structure, current handoff and feature mapping.
- Inspect core auth, catalog, cart, order, admin, upload and worker code.
- Baseline backend lint/build/unit and Flutter analyze/test verified.
- Create prioritized system audit; preserve existing data and architecture.
- Fix parser 413 classification and prevent malformed JSON from echoing body.
- Map missing FK references to non-retryable 400 and verify gallery rollback.
- Close integration resources even if storage cleanup fails.
- Separate migration image from API/worker; runtime tested non-root without
  Jest, TypeScript, Prisma CLI, application source or `.env`.
- Fix browser verifier focus/hint races; real shopping/admin flows passed.
- Assert bootstrap fixture edits; fresh migrations/seed preservation passed.
- Add guarded backup/restore verifier; local copy restored into new DB and all
  25 public tables plus schema/index/constraints match, source preserved.
- Backend 11 unit/55 integration tests and nine helper regressions passed.
- Production dependency audit zero; Gitleaks history/working-diff checks clean.
- All five real Chrome journey suites passed: shopping, admin, wishlist,
  reviews and style preferences.
- Fix malformed/NUL preview URL crash; verify 400 and server remains alive.
- Independent review completed; discovered parser leak fixed and rechecked.
- Final Web API release build passed with default `http://localhost:3000/api/v1`;
  handoff published at `docs/SYSTEM_HANDOFF.md`.

## In progress

- Resolve provider/promotion requirements and scope the remaining integrations.
- Audit remaining retention and operational failure paths.
- External provider/promotion/settlement questions remain pending.

## Completed — iteration five

- CatalogAsset reservation/receipt and dedicated public read, ADMIN multipart
  upload, input hash/replay, product/asset locking and transactional audit.
- Bounded S3 reads, hash/size verification, strict normalization, failed-upload
  cleanup that preserves verified bytes and reconciles late provider PUTs.
- Flutter file picker, preview, immutable retry key, canonical gallery/baseline
  reconciliation and managed image resolution across storefront/order widgets.
- Review caught a full-gallery rejection leaving the form locked; fixed with
  canonical reload and a concurrent-fill widget regression.
- Backend lint/build,16 unit/79 real E2E passed; Flutter317 tests passed with
  the final review regression. Browser helper had two synchronization failures
  after successful uploads; fixed by focusing the actual Flutter field before
  reading its value. Final Chrome admin run passed picker/upload/public preview,
  cover save, reload, storefront and all13 audit categories.375px screenshot
  inspected; no overflow.
- Fresh12-migration bootstrap passed, three images built, container upload/
  replay/public read plus existing runtime checks passed.29-table restore
  matches all data/schema, source unchanged:
  `wearly_handoff_1792480803907_2ad86a6e_test` →
  `wearly_restore_1792480903411_6d6b1003_test`.
- Compiled API smoke on that restored DB passed public/private route checks
  and reading the verified catalog object from the retained source bucket.
  This is not yet an object-store restore.
- Default-API Flutter release rebuilt; production dependency audit zero.

## Verified — local catalog object recovery

- Guarded helper validates matching retained bootstrap/container/DB-recovery
  evidence and a loopback private/unversioned test bucket. Refuses existing
  targets; conditional object writes do not overwrite keys.
- Actual local run exported and restored one synthetic326-byte catalog object.
  Hash/MIME/size, anonymous403 and compiled API200 using the restored DB plus
  new bucket passed. Source objects and both catalog snapshots unchanged.
- New retained bucket `wearly-restore-1792481409890-58861048-test`; archive and
  report under `.tools/handoff/wearly_handoff_1792480803907_2ad86a6e_test/objects-1792481409890-58861048/`.
- Four guard/integrity/startup/cleanup regressions passed,13 helper tests total.
  Review caught Nest's default process abort bypassing failure reporting; fixed
  and verified with a real failing-provider child process. Final actual rerun
  retained `objects-1792481707240-02dceafb` and the matching new test bucket.
  This proves local catalog recovery,
  not private Try-On, historical versions, off-host or production recovery.

## Completed — private retention follow-up

- Real MinIO regression proved a late accepted PUT could survive an earlier
  purge because purgedAt was terminal. API access stayed revoked, but physical
  bytes remained. Worker now revisits revoked tombstones after24h, retries
  failures after5min, prioritizes never-purged work and retains batch50.
- No schema, API, consent, expiry or quota change. Full80 E2E, lint/build and
  targeted8 private-image tests passed; the latter also verifies the due-time
  gate. Review found no blocker.
- Rebuilt API/worker images passed container checks on fresh bootstrap
  `wearly_handoff_1792481891987_07599963_test`. Evidence `.tools/goal-private-retention-*`.

## Completed — iteration four

- Configurable real SMTP recovery, public request/reset, one-use hashed tokens,
  all-session revocation, login/reset/refresh locking and Flutter forms.
- Security review findings addressed: bounded Redis commands/shutdown,
  malformed response uncertainty and generation-safe late response. Recent
  failed-job retry after reset cannot create a new link.
- Fixed timestamp cast timezone bug, then verified the corrected new migration
  from a fresh isolated test DB. Earlier native test DB retained, never reset.
- Fixed an existing raw pg adapter serialization-conflict retry gap discovered
  on the fresh DB: strict40001/40P01 recognition, bounded retries and generic409.
  Regression-first tests and50 real paired cart additions passed.
- Backend lint/build,15unit/71E2E; Flutter analyze/310tests,2opt-in skips passed.
  Chrome SMTP recovery and shopping/COD/mobile/reload journeys passed.
- Fresh11-migration bootstrap,3image builds, container runtime,28-table restore
  and restored-API smoke passed. Evidence `.tools/goal-recovery-*`,
  source `wearly_handoff_1792479244018_790906ee_test`, restored copy
  `wearly_restore_1792479398226_e548ec01_test`.
- Production dependency audit zero. Default-API Web release rebuilt.

## Completed — iteration two

- Persistent admin history: ten action categories, authenticated actor IDs,
  same-transaction recording, protected bounded reads.
- Dashboard history with paging, refresh, loading/error/empty states; mobile
  layout verified by widget tests and actual Chrome screenshot.
- Backend lint/build, 11 unit/58 E2E tests passed; Flutter analyze and 301 tests
  passed, two opt-in live tests skipped. Independent review found no blockers.
- Fresh nine-migration bootstrap, rebuilt images, runtime containers and real
  admin browser journey passed. Final default-API Web release build passed.
- Recovery into new `wearly_restore_1792476581460_91be3fa9_test` matched 26 public
  tables, including persisted admin activity, and schema; source unchanged.
- Evidence `.tools/goal-audit-*` and
  `.tools/handoff/wearly_handoff_1792476392334_2bab6643_test/`.

## Not completed

- External SMTP provider delivery verification.
- Remote AI workflows, promotions and settlement.
- Production configuration, production recovery evidence and final goal acceptance.

## External dependencies / blocked verification

- Real AI output: no enabled provider implementation/contract or verified account.
- External email delivery: configurable SMTP transport is implemented and local
  SMTP delivery passed; real provider credentials/domain delivery remain BLOCKED.
- Public production deployment/TLS/domain: no target or approval; deployment
  is excluded until authorized.
- Promotion policy: existing UI is percent, database is fixed VND amount.
  User clarification requested before applying financial changes.
- COD settlement: no existing verified reconciliation rule; asked whether
  staff confirmation or carrier data should authorize payment status changes.

These do not block local repairs. Goal remains active.

## Completed — iteration three

- Versioned private content drafts and explicit publication, separate public
  snapshot and transactional audit. Home title/policy use published content.
- Remote privacy/FAQ correctly describe persisted account/order data; policy
  references no longer repeat a conflicting demo return period.
- Backend lint/build/11 unit/62 E2E passed. Flutter analyze and 307 tests passed,
  including conflict, draft isolation, late response and logout cases.
- Chrome admin/content and shopping journeys passed. Review-driven PUT
  synchronization and detached-semantics scroll-helper fixes verified.
- Fresh ten-migration bootstrap, rebuilt runtime images, content publication in
  containers, 27-table recovery and restored compiled API smoke passed.
- Evidence `.tools/goal-content-*`, bootstrap source
  `wearly_handoff_1792477120268_edadebac_test`, restore
  `wearly_restore_1792477270144_c48e1b3f_test`.

## Decisions

- Work in the existing checkout on a new branch so portable SDKs, ignored local
  configuration and test services remain usable. No main branch commits.
- Native execution with regression-first changes; the supplied objective
  explicitly authorizes implementation without an additional design approval.
- Test database only for data writes; retain audit evidence, no destructive reset.
- Runtime pruning uses legacy-peer-deps **only after the full build**, because
  npm retained Prisma/TypeScript as devOptional even with omit=dev/peer.
  Container checks exercise actual runtime dependencies, including Prisma.
- Recovery compares canonical PostgreSQL constraint deparsing: pg_dump/restore
  changed redundant AND parentheses in ImageAsset_dimensions_check, with
  identical canonical expression. No constraints were weakened.
- Roles/grants, S3 recovery and off-host backup operations remain outside the
  completed local exercise; production readiness remains unclaimed.

## Evidence index

- `docs/SYSTEM_AUDIT.md`: priorities, fixes and observed checks.
- `.tools/goal-parser-green-e2e.log`: 55/55 integration.
- `.tools/goal-shopping-browser-final.log`, `.tools/goal-admin-browser.log`.
- `.tools/handoff/wearly_handoff_1792475082995_394e2eeb_test/`: bootstrap,
  containers and retained recovery reports/archive.
- `.tools/goal-production-audit.json`, `.tools/goal-secrets-*.json`.
