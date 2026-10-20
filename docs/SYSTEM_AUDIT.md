# System audit — 20/10/2026

## Scope and evidence

Objective: complete and verify the existing WEARLY system, preserving Flutter,
NestJS, current business rules and user data. Source objective:
`goal-objective.md` attached to the current Codex goal. Baseline commit:
`6eebba0`; work branch: `codex/system-completion-2026-10-20`.

This report supersedes prior acceptance claims only where new evidence is listed.
No production deployment or production data changes are authorized.

## Architecture and implemented flows

- Flutter Web, Riverpod and go_router; remote repositories for catalog,
  customer/admin sessions, profile, addresses, cart, COD orders, reviews,
  wishlist and style preferences. Demo mode is explicit and separate.
- NestJS 11, Node 24, Prisma 7, PostgreSQL 17. REST `/api/v1`, global
  validation, RBAC, Argon2id passwords, JWT refresh rotation and server-side
  session revocation.
- Orders use serializable transactions, inventory conditions, order snapshots
  and idempotency receipts. Prices are integer VND backed by decimal columns.
- Private S3 images use ownership, content validation, quotas and expiry.
  Redis/BullMQ worker handles outbox dispatch and retention. AI provider is
  disabled; this does not constitute a working AI integration.
- Twelve migrations and existing bootstrap/seed verification scripts. Local
  PostgreSQL and Memurai are available. MinIO was stopped at audit start.

## Prioritized findings

| ID | Priority | Finding | State / next action |
|---|---|---|---|
| A01 | Medium | Upload E2E cleanup throws before closing Nest/S3 when storage is unavailable; Jest remains alive | FIXED: finally closes resources; unavailable storage run exits in ~4s with failure |
| A02 | Medium | Oversized JSON returned 500; malformed JSON could echo request bytes | FIXED: 413 and safe unstructured 400 messages; three malformed inputs tested, including body-echoing errors found by independent review |
| A03 | Medium | Admin product/SKU requests with missing related UUIDs reach unhandled Prisma FK errors | FIXED: 400 INVALID_REFERENCE; E2E proves gallery transaction rollback and no orphan product/SKU |
| A04 | Medium | API/worker Docker runtime includes build tooling and test dependencies | FIXED: separate migration target and production runtime; actual API/worker verified non-root, without Jest/TypeScript/Prisma CLI/source/.env |
| A05 | Medium | Full npm audit reported 20 Moderate findings through the coverage YAML loader | FIXED: scoped js-yaml4.3.2 override removes argparse1/sprintf-js; full and production audits zero, compatibility/unit/E2E/clean image builds verified |
| A06 | High | Password recovery/email was absent | Local implementation VERIFIED: public request/reset, PostgreSQL tokens, real local SMTP/Redis worker, Flutter/Chrome; external provider delivery remains BLOCKED on configuration |
| A07 | High | Try-On/Stylist UI is gated in API mode; no real AI provider | Provider/account/contract required for real output; never substitute demo output |
| A08 | Medium | Promotions, catalog-specific upload and COD settlement were incomplete | Catalog upload VERIFIED with PostgreSQL/MinIO/Flutter/Chrome/container. Promotions BLOCKED on conflicting UI percent/schema VND contracts; COD settlement requires a confirmed rule. Activity and content draft/publication verified |
| A09 | High | Production operational verification is incomplete | Local backup/restore verified; production TLS/domain, secrets, topology, throttling, off-host backup/restore and target still require evidence |
| A10 | Low | Bootstrap helper does not assert fixture UPDATE affected-row counts | FIXED: every fixture UPDATE must affect exactly one row; fresh bootstrap passed |
| A11 | Medium | Shopping browser verifier races Flutter focus/input replacement and assumes label excludes hint | FIXED: wait for focus frames, match address label with optional hint; full Chrome shopping passed |
| A12 | Low | Local preview crashes on malformed percent escapes or NUL paths | FIXED: invalid URL returns 400; live process probe confirms subsequent homepage still returns 200 |
| A13 | Medium | Admin activity history exists only in demo memory | FIXED: transactional event recording for all ten admin mutation categories, ADMIN-only paginated read and dashboard history; PostgreSQL, widget, Chrome, container and recovery verification passed |
| A14 | Medium | Content drafts only live in demo memory; no explicit remote publication | FIXED: versioned private drafts, separate published snapshot, ADMIN save/publish, public home title/policy, transaction audit |
| A15 | Medium | Remote privacy/FAQ still claim orders and account data disappear on reload | FIXED: API-mode text describes persisted data and COD accurately; return-policy links use the published policy page |
| A16 | High | Raw PostgreSQL adapter serialization conflicts bypass P2034-only retry and return500 on concurrent cart additions | FIXED: explicit 40001/40P01 adapter conflict detection, five-attempt bound, generic409 when exhausted; red/green unit tests, 50 real concurrent pairs and full E2E passed |
| A17 | Medium | Recovery Redis producer shutdown fails after a stalled established connection | FIXED during implementation: command/deadline bounds and forced disconnect; real TCP proxy regression passes and Jest exits normally |
| A18 | Medium | Private image cleanup permanently skips purged tombstones, leaving bytes if a remote PUT completes after DELETE | FIXED: revoked tombstones reconciled every24h,5min failure retry, never-purged priority/batch50; real PG/MinIO red→green regression, API remains404 |

No Critical issue has been confirmed. High items remain open; the goal is
**not complete**, and production readiness has not been established.

### Iteration four evidence

- Backend lint/build, **15 unit + 71 real E2E** passed; PostgreSQL/Redis/MinIO
  and SMTP receiver used. Flutter analyze clean, **310 tests passed**, two
  live opt-in tests skipped.
- Chrome recovery passed actual mail link → URL scrub →375px reset →new login;
  old password/session and reused link rejected. No external email sent.
- Security review findings fixed and re-reviewed: Redis response deadlines,
  malformed reset response treated as uncertain, generation-safe late response.
- Recovery's initial timestamp cast caused a seven-hour timezone error; raw
  timestamptz fixes it. Corrected uncommitted migration tested from an empty
  isolated DB; original test database retained without reset.
- A fresh eleven-migration bootstrap/schema diff/seed replay passed:
  `wearly_handoff_1792479244018_790906ee_test`.
- Production dependency audit after Nodemailer addition remains **zero**.
- Evidence `.tools/goal-recovery-*`; [recovery configuration](password-recovery.md).

### Iteration five evidence

- Dedicated CatalogAsset reservation/receipt, ADMIN upload and verified public
  reads. Private bucket and private-user asset separation verified. Failed
  uploads cannot publish; transactional audit rollback and late PUT cleanup
  tested. Asset/product locks prevent duplicate uploads and gallery overfill.
- S3 body deadline/byte limit tested against actual oversized/stalled HTTP
  responses; hash/size verified before public delivery.
- Backend16 unit/79 E2E; Flutter analyze and317 tests passed, two opt-in skips.
  Review found a full-gallery rejection locking the form; fixed and regression
  added. No other backend/frontend blocking finding.
- Chrome verified actual picker/upload/preview/cover persistence, mobile375px
  and desktop, storefront and13 audit types. Two initial helper failures were
  transient toast/Flutter input focus assumptions; corrected and rerun passed.
- Twelve migrations/bootstrap, three runtime images and container catalog
  upload/replay/read passed. Restore29 public tables and schema matched:
  `wearly_restore_1792480903411_6d6b1003_test`. Source DB unchanged.
- Compiled restored API passed readiness/public/private routes and public
  catalog read against the retained source bucket. Object-store restore still
  needs separate evidence. Production dependency audit remains zero.
- Evidence `.tools/goal-catalog-*`; [catalog images](catalog-images.md).

### Local object recovery evidence

`verify-object-recovery.cjs` passed against the retained catalog bootstrap and
restored DB. One326-byte verified catalog object was exported to disk and
restored into new private bucket `wearly-restore-1792481409890-58861048-test`.
Exact hashes/MIME/size, anonymous403 and compiled API200 passed; source objects
and both catalog metadata snapshots unchanged. Four guard/integrity/startup/
cleanup tests pass. Review's Nest startup-abort finding fixed;13 helper tests
and final actual run `objects-1792481707240-02dceafb` passed.
Evidence `.tools/goal-object-recovery.log` and the source handoff's `objects-*`
directory. A09 remains open for production/off-host/private-image recovery.

### Private retention follow-up

- Reproduced A18: after a lost upload acknowledgement and successful purge, a
  simulated late provider PUT remained in MinIO after the old worker sweep.
- Fixed using existing purgeRetryAt; no schema/API/consent/quota change.
  Never-purged work precedes periodic reconciliation. Test verifies no premature
  retry, physical removal when due, continued private404 and next schedule.
- Backend lint/build, full80 E2E and targeted8 private-upload tests passed.
  Independent review found no blocker. Rebuilt API/worker images passed runtime
  verification on fresh `wearly_handoff_1792481891987_07599963_test`.
- Evidence `.tools/goal-private-retention-*`. Earlier catalog DB/object recovery
  remains the latest recovery evidence; this follow-up did not change schema.

### Dependency tooling follow-up

- Scoped only load-nyc-config's YAML dependency to4.3.2. Direct Jest/ts-jest
  versions and the Swagger-specific override are unchanged. Lockfile removes
  argparse1/sprintf-js; no forced downgrade.
- Actual loader test verifies inherited YAML arrays, flags, numeric thresholds
  and malformed-input rejection. Backend lint/build,17 unit and80 real E2E
  tests passed; independent review found no actionable compatibility issue.
- Full and production npm audits both report zero vulnerabilities. Three
  images rebuilt using clean npm-ci from the new lockfile. Fresh twelve-
  migration bootstrap and container API/worker/COD/content/catalog checks
  passed on `wearly_handoff_1792482185306_60f38cdd_test`.
- Evidence `.tools/goal-toolchain-*`; historical audit counts below describe
  earlier revisions. This is dependency advisory coverage, not a penetration test.

## Baseline verification observed in this session

- Backend lint, build and 11 unit tests: passed.
- Flutter analyze: no issues. Flutter tests: 299 passed, 2 live opt-in skipped.
- Backend E2E with worker/storage: 47 passed, 6 failed because MinIO was not
  listening; cleanup also failed and left Jest alive. This is a failed run.
- `npm audit`: 20 Moderate, 0 High, 0 Critical. Raw local evidence:
  `.tools/goal-dependency-audit.json`.
- Logs: `.tools/goal-baseline-{analyze,flutter,e2e}.log`.

### Verified after repairs

- Backend lint/build and 11 unit tests passed; **55/55 E2E** passed with
  PostgreSQL, Redis and MinIO (`.tools/goal-parser-green-e2e.log`).
- Chrome customer journey passed registration/address/cart/COD/cancel/re-login,
  375/1440px and resize; admin journey passed taxonomy/product/gallery/SKU/stock,
  order transitions, persisted records and independent shopper/admin logout.
- Chrome wishlist, review/history and style journeys passed, including account
  isolation, persistence after reload, mobile layouts and stale style conflict.
- API, worker and migration images built. Actual runtime checks and COD/outbox
  verification passed; test containers stopped and retained.
- Bootstrap with affected-row assertions passed on
  `wearly_handoff_1792475082995_394e2eeb_test`: eight migrations, schema diff zero,
  seed replay preserves all business tables.
- Backup restored into **new** `wearly_restore_1792475826933_1e4e0c3e_test`:
  data hashes/counts for all 25 public tables (including migrations), column
  definitions/lengths, enum definitions, constraints and indexes match; source
  unchanged. Compiled API read-only smoke also passed on an earlier restored
  copy (`wearly_restore_1792475591507_edcf74ac_test`).
- Nine Node helper regression tests passed (seven container failure paths, two
  recovery safety guards). Production npm audit: **0** vulnerabilities.
- Gitleaks scanned 63 reachable commits and the tracked working diff with no
  findings. This is not a claim of a complete penetration test.
- Recovery evidence is retained in `.tools/handoff/<source>/`; raw logs and
  browser evidence are ignored local artifacts. No business DB was reset.

Operational caveats: Prisma's pg adapter emits a pg deprecation warning during
some concurrent transaction tests; current tests pass, but recheck before a pg
major update. Dev/migration images retain development dependencies; the earlier
20 Moderate findings are resolved by the tooling follow-up above. Runtime source maps are compiled artifacts; `.env`
and source directories are absent. TLS, external mail/AI/payments and
production infrastructure remain unverified.

Independent review found the malformed JSON body-echo case, which was reproduced
before repair and verified after repair. Follow-up review reported no blockers
in the changed scope. This does not close the open functionality/production
items above. Roles/grants, S3 recovery, off-host backups and load testing were
not part of the local recovery verification.

## Security review boundaries

Reviewed auth/guard, validation, transaction, product queries, cart/orders,
admin writes, upload ownership and worker error sanitization. Product search
uses parameterized SQL; server prices/stock determine checkout. Tokens are
memory-only in Flutter and not automatically persisted. Further operational,
dependency and browser verification is tracked in IMPLEMENTATION_PROGRESS.md.

## Iteration two: persistent administration activity

- Additive migration `20261020100000_admin_audit`; no existing rows/columns
  changed. Applied only to dedicated test databases during verification.
- Actor UUID comes from the authenticated session. Only action, target UUID
  and timestamp are stored; no payload, credentials or customer address copied.
- Successful business writes and their event share one transaction. Rejected
  concurrent taxonomy/stock/order writes add no success event. An actual failed
  audit insert rolls back product metadata and gallery replacement.
- Historical UUIDs deliberately have no cascading FK. No event mutation API;
  this is application history, not an independent tamper-proof compliance store.
- Backend lint/build/11 unit tests and **58 E2E** passed. Flutter analyze clean,
  **301 tests** passed, two opt-in live tests skipped.
- Fresh bootstrap `wearly_handoff_1792476392334_2bab6643_test`: all nine migrations,
  schema diff zero, seed replay preserves all 25 business tables.
- Independent review found no actionable correctness/security issue in this
  scope. Evidence: `.tools/goal-audit-*`.
- Real Chrome admin journey passed all existing mutations and activity refresh;
  database assertions cover all ten action categories and exact actor IDs.
  Mobile history screenshot inspected, no horizontal overflow.
- Rebuilt API/migration/worker images passed the runtime suite, now including a
  successful admin write and persisted activity event. Containers stopped.
- Backup restored into new `wearly_restore_1792476581460_91be3fa9_test`, matching
  all **26 public tables** including non-empty history and migration records,
  schema, enums, constraints and indexes. Source unchanged.
- Final Flutter Web release build passed and restored default local API URL.

## Iteration three: content draft/publication

- Additive `20261020110000_store_content` migration; fixed storefront key, no
  automatic seed/publication of policy text. Content fields are plain text.
- ADMIN-only GET/PUT draft and POST publish. Mandatory expectedVersion rejects
  stale saves/publications and concurrent first-save/publish races. Publication
  copies the saved revision; later drafts stay private. Public GET selects only
  published columns, never draft contents or actor IDs.
- `CONTENT_DRAFT_SAVED` and `CONTENT_PUBLISHED` events commit with content
  changes. Real PostgreSQL audit failure rolls back a publication.
- Flutter separates Save draft from Publish; unsaved fields disable Publish.
  Conflicts/uncertain writes require rereading, no automatic write replay.
  Late publication completion refreshes public content even after page/session
  disposal. Public load errors show retry instead of reverting to demo copy.
- Backend lint/build/11 unit tests and 62 E2E passed. Flutter analyze and full
  **307-test run** passed, including logout during publication. Two opt-in live
  tests remain skipped in the ordinary suite.
- Actual Chrome validated draft privacy, published home/policy, later-draft
  isolation and all twelve audit actions. Review found a browser synchronization
  gap, fixed by awaiting successful PUT responses; implementation had no blocker.
- Fresh bootstrap `wearly_handoff_1792477120268_edadebac_test` passed all ten
  migrations, schema diff and seed preservation. Rebuilt images passed container
  auth/COD/worker, audit and draft/publication checks.
- Recovery into `wearly_restore_1792477270144_c48e1b3f_test` matched all 27 public
  tables and schema, including non-empty draft/published content and events.
  Source retained unchanged. Evidence: `.tools/goal-content-*`.
- Compiled API smoke on that restored database passed readiness/catalog/public
  content and unauthorized private routes. No writes during the smoke run.
- Chrome shopping regression passed registration/address/cart/COD/cancellation
  and restored order after login. Its first run failed on a detached Flutter
  semantics element after order creation; helper now scrolls the actual viewport
  with bounded fresh locator checks. Re-run passed; no commerce API change.
