# Store identity and local HTML implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish configurable truthful store identity/policies and inspect safe local product HTML.
**Architecture:** Extend existing StoreContent publication; consume published details in Flutter and Nest HTML. Preserve current authorization/versioning.
**Tech Stack:** Nest11/Prisma7/PostgreSQL17, Flutter3.47.7, native Windows tools.
**Spec:** docs/superpowers/specs/2026-10-22-store-identity-design.md

## Global Constraints

Local only; WEARLY demo default, blank contacts, no real merchant promises.
No provider calls, production deployment or indexing submission.
One nullable JSON pair in migration27; old client omission preserves details.
No API/build changes during E2E; Flutter serial; source/env preserved.
Use existing isolated worktree. One final reviewer only, no implementer agents.

## Review Focus

1. Old clients saving banner/policy must not erase published or draft identity.
2. Null/malformed nested details and unknown fields must fail before persistence.
3. Failed/stale publication and logout must not expose drafts as public truth.
4. Hostile product/store text and Host headers must not inject HTML or canonical URLs.
5. Missing contacts and stale FAQ must not imply real shipping/payment/AI guarantees.

### Task1: typed identity publication

Files: backend/prisma/schema.prisma,migrations/20261022010000_store_identity/migration.sql;
backend/src/modules/content/{content.dto,content.service,store-details}.ts;
backend/test/content.e2e-spec.ts; frontend/lib/app/{content_provider,store_details}.dart.
Produces details contract in spec; omission=>preserve, null=>400; published fields only.

- [x] Add meaningful failing content E2E assertions for defaults, invalid details,
  draft isolation, publishing details, legacy omission and stale version.
- [x] Run targeted E2E via existing native test harness; inspect expected RED.
- [x] Add nullable columns, typed validation/defaults and copy-on-publish. Generate
  client/apply test migration only; rerun content tests GREEN, lint/build; commit.

### Task2: published storefront and editor

Files: frontend/lib/features/admin/remote/content_page.dart; core/widgets/
{store_content,store_shell}.dart; features/info/{info_page,support_pages,
remote_contact_page}.dart; app routes; test identity widget/provider tests.
Consumes API details; produces public name/contact/policies and admin editing.

- [x] Add failing widget/provider tests for details, blank-contact hiding, public
  defaults, policy/terms rendering, editor request and no draft leak.
- [x] Implement details model/editor/public consumers, accurate FAQ and terms route,
  retaining existing layout/loading/errors/version checks. Tests GREEN.
- [x] Flutter analyze/tests, responsive browser acceptance; commit.

### Task3: HTML previews, migration and final acceptance

Files: backend/src/modules/content/storefront-{controller,service}.ts,content.module.ts;
config/env.validation.ts,.env.example; backend/test/storefront.e2e-spec.ts;
frontend/web/index.html; tools acceptance/browser as needed; docs guides/progress.
Produces GET /api/v1/storefront/products/:slug,sitemap.xml,robots.txt; explicit
noindex/no-store. Configured loopback origins only, trusted published content.

- [x] Add failing HTML tests for escaped values, trusted origins, unpublished name,
  inactive/missing404, sitemap active-only/absolute URLs and noindex headers.
- [x] Implement rendering/routes/config; use ProductsService, bounded50000 sitemap,
  escaped plain text and no scripts. Targeted tests GREEN; commit.
- [x] Fresh native business backup, apply additive migration27 without seed; compare
  preexisting data/columns and env hashes. Run full acceptance and native browser
 375/1440, record precise provider/CI limitations and operator guide.
- [x] One fresh strongest-model review of whole milestone with Review Focus,
  regrade by user effect, one RED->GREEN fix pass; preserve ledger, cleanup only
  own scratch and commit. Continue configured-provider acceptance/root integration.

Self-check: three tasks cover all spec surfaces; backend default details and
Flutter fallback must match; missing/blank published long-form policies display
truthful default rather than an empty page. Contact blanks remain hidden.
