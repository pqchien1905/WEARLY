# Product reviews implementation plan

> Use executing-plans inline with TDD and one fresh final review. User authorizes continued completion of WEARLY.

**Goal:** Customers who received a product can publish, edit and delete their own review; shoppers can read real ratings/comments on product pages.
**Architecture:** Existing Review table and shopper identity; Nest module with public paginated read and private owner endpoints. Flutter repositories/providers separate public reads from shopper eligibility and mutations. No new dependencies; add a product/date index only.
**Spec:** Original WEARLY master prompt reviews backlog, continuation authorization, and implementation choices below. Optional question about pre-moderation was asked; default is immediate publication unless user steers otherwise.
**Tech stack:** Existing NestJS, Prisma/PostgreSQL, Flutter/Riverpod.

## Design and constraints

- Only an order with DELIVERED status containing a variant of the product qualifies, regardless of COD payment settlement. Admin-only session does not unlock shopper review UI. One review per account/product, enforced by existing uniqueness.
- GET `/products/:productId/reviews` is public (UUID), page/limit default1/5, max20. Only active products with active SKUs. Response `{items:[{id,rating,comment,createdAt,updatedAt}],total,page,limit,average}`; average null for no reviews, otherwise one decimal. Include only reviews backed by a delivered purchase, including legacy rows. No userId, name, email, order or address disclosed; UI labels each author 'Khách đã mua hàng'.
- GET `/products/:productId/reviews/me` returns `{review,canReview}` for current shopper; no cross-account authority accepted. Own review remains readable/removable if product is hidden, but create/edit then fail404. Public reads never send tokens.
- POST `/products/:productId/reviews` creates `{rating,comment}`; integer1–5, trimmed comment1–2000 characters. Duplicate409; unqualified403. PATCH `/products/:productId/reviews/me` requires `{rating,comment,expectedUpdatedAt}`; DELETE same path requires `{expectedUpdatedAt}`. ISO timestamp compare-and-set, monotonic updatedAt; stale409, unknown own review PATCH404, repeated DELETE succeeds. No auto replay after uncertain network outcomes.
- Transactions serialize owner writes and verify delivered purchase. Public items/count/average share a repeatable-read snapshot; sort createdAt desc/id desc. Add non-destructive Review(productId,createdAt,id) index.
- UI: review section between product information and recommendations, plum stars, large rating/count, left-aligned readable comments (max720px), bordered editor only when needed. Reuse Manrope/BeVietnamPro, canvas #F7F8F7, white #FFFFFF, ink #252329, plum #65394D, line #DFDCE0. At375px stack summary/actions/list; at1440px summary and comments share width without cramped text.
- Explicit loading, empty, read failure/retry, guest login return path, purchase requirement, own-review edit/delete confirmation, validation and unknown-result reload. Cancel/close must not leak private state; late responses from old shopper sessions ignored. Invalidate public review caches after every settled write even if page/session disappears. Reset pagination on mutation/reload; no demo fixture reviews in API mode.
- Existing demo unchanged. This phase does not implement moderation queues, uploads in reviews, merchant replies, rating sort/filter or review notifications. Other browser sessions refresh to see changes.

## Review focus

- Delivered purchase ownership vs pending/cancelled orders; existing unverified rows; private identity never present in public responses.
- Concurrent creates/edits/deletes and sub-millisecond timestamp collisions; stable pages and aggregate consistency.
- Lost response after commit, session loss/relogin with same user, page/dialog disposal; no stale public cache or private state restoration.
- Empty/error/hidden product, last-page deletion, long comments, mobile keyboard/viewport; no misleading rating zero or fake content.
- Integration with independent staff/customer auth and existing product/order routes; no unrelated commerce behavior regressions.

### Task 1: Review API
Files: backend/src/modules/reviews/{reviews.module,reviews.controller,reviews.service,review.dto}.ts, app.module.ts, prisma/schema.prisma and migration; backend/test/reviews.e2e-spec.ts.
- [ ] Write PostgreSQL tests: public empty/privacy/pagination/average; guest/ownership/eligibility/validation; duplicate/concurrent operations; stale edits/deletes; hidden/legacy data. Run tools/test-backend.ps1, expected RED missing endpoints.
- [ ] Implement contracts above and safe index. Run backend E2E, unit, build/lint, expected PASS. Commit.

### Task 2: Review state and UI
Files: frontend/lib/data/remote_reviews.dart; app/review_providers.dart; features/product_detail/product_reviews.dart and review_editor.dart; product_page.dart; tests/reviews_test.dart and reviews_ui_test.dart.
- [ ] Write repository/session and UI regressions first; observe RED. Cover anonymous public reads, own data and mutation lifecycle, errors/unknown outcomes, no staff-only access, create/edit/delete and mobile layout.
- [ ] Implement typed responses, shopper-bound repository/provider, public cache revision invalidation and responsive review UI. Add a product information shortcut to scroll to reviews.
- [ ] Full Flutter suite and analyzer expected PASS; commit.

### Task 3: Live end-to-end verification and documentation
Files: tools/verify-reviews-browser.cjs; tools/test-frontend-api.cjs; README/docs/api.md/docs/migration-plan.md/docs/progress.md.
- [ ] Extend synthetic test fixture with delivered order and second account. Browser verifies guest, ineligible, buyer publish/edit/delete, reload persistence, public aggregate and responsive screenshots. Cleanup only this run's reviews before users/products; test database only.
- [ ] Run Chrome/PostgreSQL; inspect375/1440 screenshots, expected PASS. Restore normal localhost3000 release, apply non-destructive index and restart only owned backend process; preserve user Flutter.
- [ ] Document evidence/limits, fresh whole-branch review and important fix pass with RED/GREEN, integrate and push under prior authorization.
