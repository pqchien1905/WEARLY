# Persistent wishlist implementation plan

> Use executing-plans inline, test-driven-development and one fresh final review. User authorizes continued completion of remaining WEARLY features.

**Goal:** Finish the existing wishlist flow end to end: save/remove from product cards, details and cart, browse saved products, retain across login, isolate shopper accounts.
**Architecture:** Existing WishlistItem schema, owner-only GET/PUT/DELETE Nest module, idempotent set/remove under per-user transaction lock. A dedicated shopper-scoped ChangeNotifier uses the existing ApiClient and public catalog decoder. Keep demo wishlist behavior and existing UI tokens.
**Spec:** Original master request (preserve Flutter, complete real API flows), docs/migration-plan.md wishlist backlog, user's continuation authorization. Implementation choices below are ours.
**Stack:** Existing Flutter/Riverpod/NestJS/Prisma/PostgreSQL; no new dependency or migration.

## Design and constraints

- GET /wishlist and PUT/DELETE /wishlist/:productId return `{items:[{productId,product:CatalogProduct|null}],limit:200}` sorted newest first with ID tie-break. Only the current user's rows. No userId accepted as authority.
- Cap at 200 saved rows per user, enforced under lock. Full bounded snapshot keeps hearts/list coherent; UI pages 12 records. Already-saved PUT and absent DELETE are idempotent. No bulk clear exposed.
- Add only active products with active variants; out-of-stock can be saved. Hidden/no-active-variant products remain as removable generic unavailable placeholders, without unpublished metadata. Existing rows are never deleted merely because products are hidden.
- Use the customer session only, including ADMIN shopping separately. Sign-out/account switch clears local state and ignores late reads/writes; admin-only login neither loads nor authorizes shopper wishlist.
- Heart updates only on acknowledged mutation. Errors are shown with retry; unknown network outcome does not silently flip hearts. A subsequent refresh reconciles before another toggle. Cart save does not remove an existing favorite or cart item.
- Guest heart opens customer login with current safe return path. After login user can save explicitly. No pretend guest persistence.
- Retain Manrope/BeVietnamPro, plum #65394D, canvas #F7F8F7, ink #252329. Reuse product grid/buttons; explicit loading/error/empty/unavailable states at 375/1440 widths.

## Review focus

- Concurrent quota/idempotent adds and deletes must not create duplicates or cross account boundaries.
- A network failure after server commit must not cause a stale toggle to undo the user's choice.
- Logout/relogin with the same email and delayed responses must not restore old state.
- Hidden products, zero active variants, out-of-stock and last-item deletion on later pages remain usable.
- Cart drawer navigation and customer/admin isolation must retain existing shopping behavior.

### Task 1: Owner-scoped wishlist API
Files: backend/src/modules/wishlist/{wishlist.module,wishlist.controller,wishlist.service}.ts; backend/src/app.module.ts; backend/test/wishlist.e2e-spec.ts.
- [ ] RED tests: guest 401, invalid UUID400, cross-account isolation, concurrent idempotency/quota, hidden placeholders/removal, re-login persistence. Run tools/test-backend.ps1; expected missing endpoint failures.
- [ ] Implement bounded snapshot and transactional mutations using existing catalogInclude/productJson and lockUser. No schema changes. Backend E2E/build/lint expected PASS.
- [ ] Commit backend contract.

### Task 2: Shopper wishlist state and UI
Files: frontend/lib/app/remote_wishlist.dart; core/widgets/wishlist_button.dart; features/catalog/remote_wishlist_page.dart; product_card/product_page/cart_page, route gate and remote_catalog decoder; frontend/test/remote_wishlist_test.dart and remote_wishlist_ui_test.dart.
- [ ] RED tests for persistence/state, token/account replacement and late responses, failure/reconciliation, true-save idempotency, route/login gate and responsive page. Existing demo tests must remain valid.
- [ ] Implement disposal/generation-aware controller with one serialized mutation, no optimistic changes, explicit load/mutation errors. Reuse public product decoder. Wire all existing save entry points; resolve cart product by slug before save.
- [ ] Run focused tests, analyzer and full Flutter suite; expected PASS. Commit.

### Task 3: Integration verification and documentation
Files: tools/verify-wishlist-browser.cjs, tools/test-frontend-api.cjs, docs/api.md, docs/migration-plan.md, docs/progress.md, README.md.
- [ ] Real Chrome/PostgreSQL: register/login, save from card/detail/cart, browse/remove, reload/login persistence, logout/second-account isolation; inspect375/1440 and resize. Only unique _test fixtures.
- [ ] Build normal localhost3000 release, refresh owned backend, update capability/backlog docs. One independent final review; fix important findings with RED/GREEN regressions. Integrate/push authorized repository.
