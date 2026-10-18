# Flutter API administration implementation plan

> **For agentic workers:** Use executing-plans inline, followed by one fresh whole-branch review. Track completion below.

**Goal:** Let an authorized administrator manage the real catalog, inventory and order lifecycle from the existing Flutter admin area.

**Architecture:** Retain demo pages and AdminShell; API mode selects dedicated admin pages with a session-bound repository and Riverpod async providers. Extend NestJS admin contracts with full detail and aggregate reads. Product metadata, SKU changes and inventory adjustments are separate explicit saves.

**Tech stack:** Existing Flutter/Riverpod, NestJS, Prisma and PostgreSQL; no new runtime dependencies.

**Spec:** User's backend master prompt at `C:/Users/Nobita/.codex/attachments/1064c7c6-b822-43ba-a47a-80403e150132/Pasted text.txt`, existing `docs/migration-plan.md`, and continued authorization to complete WEARLY.

## Global constraints

- Work in the actual `D:/Fashion Shop` checkout on a feature branch; preserve Flutter UI, mock behavior and existing customer flows.
- Server verifies ADMIN on every request. Anonymous/customer routes cannot load admin data. Tokens remain in memory and late responses cannot cross sessions.
- Test writes use a separate database ending `_test`. Do not reset business data.
- Exact VND integer strings; quantity/order versions come from the server. Conflicts require reload; never silently retry stock/status writes.
- Hide products/SKUs rather than deleting historical records. Delivery does not mark COD paid.
- No promotion, content, AI-provider or payment-settlement simulation in API admin mode.
- User authorized ADMIN for the email provided in the conversation; grant only to that existing account, never create a shared password or publish the private email in repository documentation.

## Review focus

- Disabled variants must remain visible to administrators and absent from public catalogs.
- Concurrent stock/order edits must reject stale versions without duplicate movements.
- Session changes during reads/writes must discard old responses and data.
- Editing metadata must preserve unrelated gallery images; invalid gallery replacement must roll back atomically.
- Empty/multiple pages, long content and mobile widths must remain usable; totals must describe the full database rather than one page.

### Task 1: Complete server administration contracts

**Files:** admin controller/service/DTO, `backend/test/admin.e2e-spec.ts`, `tools/grant-admin.cjs`.
**Interfaces:** GET `/admin/summary`, `/admin/products/:id`, `/admin/orders/:id`; existing paginated lists retain raw Prisma JSON. Product writes accept optional `images: [{url,alt,color?}]`, ordering by array index. SKU list includes inactive variants. Summary returns products, inventoryUnits, orders, pendingOrders, customers counts. Grant tool takes one existing email, revokes its sessions and grants ADMIN in a transaction.

- [x] Write/run PostgreSQL E2E: authorization, detail of hidden SKU, gallery validation/rollback, stock conflict, legal order transitions and pending COD, full counts and safe users. Expected initial failure: missing routes/gallery contract.
- [x] Implement contracts and grant helper. Run backend lint/build, dedicated E2E. Expected pass; no database migration required.
- [x] Commit `feat: complete secure administration API contracts`.

### Task 2: Session-bound Flutter admin data

**Files:** `frontend/lib/data/remote_admin.dart`, `frontend/lib/features/admin/remote/admin_providers.dart`, `frontend/test/remote_admin_test.dart`.
**Interfaces:** AdminRepository exposes list(kind,page), detail(kind,id), summary(), references(), product/SKU/stock/status mutations through ApiClient. Typed AdminPage wraps items,total,page,limit. Providers auto-dispose and watch account identity; all calls authenticated and reject changed sessions.

- [x] Write/run tests for exact mutation bodies/versions, pagination, inactive SKU parsing and late-session rejection. Expected initial failure: missing implementation.
- [x] Implement repository and providers with distinct resource keys and explicit invalidation after mutation. Expected tests pass.
- [x] Commit `feat: add isolated Flutter administration data access`.

### Task 3: Real administration screens

**Files:** remote admin route/pages/product editor/widgets, remote route gate, admin shell, `frontend/test/remote_admin_ui_test.dart`.
**Interfaces:** API admin routes require signed-in ADMIN. Dashboard displays counts; lists paginate products/inventory/orders/users; product editor saves metadata/gallery separately from create/edit SKU and stock; order detail exposes only the next legal status. Errors and reload remain visible, buttons disable during save. Unknown demo-only admin routes show unavailable state.

- [x] Write/run widget tests for gate, list/pagination, product save, stock conflict, order transition and mobile overflow. Expected initial failure: routes still unavailable.
- [x] Implement pages using existing tokens/primitives and responsive cards; preserve mock routes. Test analyzer and all Flutter tests. Expected pass.
- [x] Commit `feat: connect Flutter administration screens to PostgreSQL`.

### Task 4: Real browser verification and handoff

**Files:** `tools/test-frontend-api.cjs`, admin browser verifier, README and API/progress/migration documentation.
**Interfaces:** Disposable synthetic admin fixture in `_test`, real API and release Chrome at 375/1440 widths. Cleanup only owned fixture IDs. Backend remains configured for native PostgreSQL.

- [x] Exercise real login, create/edit product and SKU, stock adjustment, order transition and reload, customer access rejection. Build normal release for localhost:3000 afterwards.
- [x] Run required backend/Flutter checks; grant ADMIN to the authorized existing account if present. Update accurate documentation and commands from root/frontend.
- [x] Commit verification/docs; request one fresh final review, fix important findings with regressions, merge/push authorized main.
