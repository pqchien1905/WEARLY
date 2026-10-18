# Admin category and brand management

> Execute inline with dev-flow; one fresh final review. Continued work is authorized by the user.

**Goal:** Create and rename categories and brands in the existing administration UI, select them in product forms, and show real categories in the storefront.
**Spec:** User's continued completion request and original WEARLY master prompt. Preserve Flutter and independent shopper/admin sessions.
**Architecture:** Existing Category/Brand tables; no migration or dependency. Protected paginated admin endpoints; public array endpoints remain compatible. Reuse current admin cards, dialogs, plum accents, typography and responsive shell.

## Constraints

- GET/POST `/admin/categories` and `/admin/brands`; PATCH `/:id` renames only. Create accepts name (trimmed, 1–100) and stable lowercase ASCII slug (1–100). Duplicate slug returns 409; unknown ID 404; unauthorized 401/403.
- Rename accepts `{name, expectedName}`. Atomically compare the displayed old name so a stale editor cannot silently overwrite a different name. Slug/ID and product associations are immutable. No deletion in this phase.
- List returns `{items,total,page,limit}`, sorted name/ID consistently in one repeatable-read transaction; include product count. Separate paged list state per route.
- UI supports loading, empty, error/retry, validation, duplicate/conflict/unknown-write recovery, pagination and session loss. Invalidate product references and public catalog after a save or uncertain-write reload.
- Public home/shop categories come from the API in remote mode, without fixture fallback on errors; demo remains unchanged. No change to customer login or wishlist semantics.

## Review focus

- Privilege checks, stale concurrent rename, duplicate slug, validation and immutable links.
- Dialog closure/logout during writes, late responses, unknown write outcome and cache refresh.
- New categories/brands usable in product forms and storefront, including pagination, empty lists and 375 px width.

### Task 1: Taxonomy API
Files: admin controller/service/DTO; backend/test/admin.e2e-spec.ts.
- Write contract tests and run tools/test-backend.ps1. Expected RED for missing endpoints.
- Implement bounded stable pagination, create and atomic rename; run PostgreSQL E2E, build/lint. Expected PASS.
- Commit backend API and plan.

### Task 2: Admin UI and storefront categories
Files: remote admin repository/providers/pages, shell/routes, public category provider/widgets, tests.
- Write focused UI/API tests; run them and observe RED.
- Add two admin pages/dialogs and dynamic public category choices, preserving demo UI and separate sessions.
- Run focused tests, full Flutter suite and analyzer. Expected PASS. Commit implementation.

### Task 3: Live verification and documentation
Files: tools/verify-admin-browser.cjs, tools/test-frontend-api.cjs; README and progress documentation.
- Extend synthetic-fixture browser workflow to create/rename both taxonomies, assign to a product and browse category at desktop/mobile widths. Clean up only owned fixtures.
- Run real Chrome/API/PostgreSQL verification; inspect screenshots. Expected PASS, usable layout.
- Restore normal localhost:3000 build and update owned backend runtime, preserve user's Flutter process.
- Record evidence, one final fresh review, fix important findings with RED/GREEN tests, then integrate and push under prior authorization.
