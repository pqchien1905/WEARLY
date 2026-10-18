# Customer review history implementation plan

> Use executing-plans inline, TDD and one fresh final whole-branch review. Continuation authorized by user: complete missing functionality.

**Goal:** A customer can find and manage all their existing reviews, including removing reviews of unavailable products.
**Architecture:** Extend existing Reviews module and shopper-bound repository; reuse ReviewEditor, account layout and revision invalidation. No new dependencies or duplicate auth/mutation flows.
**Tech stack:** NestJS, Prisma/PostgreSQL, Flutter/Riverpod, existing Chrome harness.
**Spec:** Existing review rules in docs/reviews.md and the missing personal-review management screen noted in the last completed phase. User authorized filling gaps. Immediate publication remains explicitly confirmed. Implementation choices below are the assistant's defaults; optional priority question does not block work.

## Design and global constraints

- GET `/api/v1/users/me/reviews` requires current authenticated identity; page1/limit5 default, max20, reuse ReviewPageDto. Repeatable-read count/items; order createdAt desc/id desc. Only current user's reviews, including unverified legacy rows (can delete, cannot edit without delivered order).
- Response `{items:[{id,rating,comment,createdAt,updatedAt,productId,product:{name,slug}|null,canEdit}],total,page,limit}`. Never return email, userId, order details or hidden product metadata. Product is null if inactive or no active SKU; out-of-stock active SKU stays available. canEdit = available and delivered purchase of same product. Existing PATCH/DELETE owner endpoints enforce authority and timestamp CAS.
- Add non-destructive index Review(userId,createdAt,id); deploy to test/native without resets.
- Flutter OwnerReviewRepository.history(page) preserves generation/disposal guards. New owned history provider watches review revisions and shopper repo; logout/account switch cannot restore private rows. Any mutation, including late completion after timeout, refreshes public and personal queries.
- Add `/account/reviews`, link in AccountNavigation only in API mode. Direct route in demo explains that reviews require online mode; no fake history. Guest/staff-only session requires customer login and preserves safe return path.
- AccountFrame with existing Manrope/BeVietnamPro, canvas #F7F8F7, ink #252329, plum #65394D, line #DFDCE0. Left-aligned list max840px, product title, accessible star rating, date and multiline comment; action buttons wrap at375px. Reuse editor and deletion confirmation. Unavailable product has generic label, no link/edit, delete retained.
- Loading/empty/error/retry and explicit refresh; reset to page1 after editor closes, page recovery if current page empties. Independent staff session unchanged. No private stale rows shown during refresh/account change. Other browsers need reload as before.
- This increment does not add review images, replies, moderation, promotions, email services, AI/payment providers. Those remain separately tracked; no claim of project-wide completion.

## Review focus

- Cannot list another user's reviews via query/route injection; legacy own reviews visible without new edit rights.
- Hidden product metadata not exposed and owner can delete; no-SKU and zero-stock differ.
- Stable pagination/ties and last-page deletion; concurrent count/list consistency.
- Logout/account changes during read/write and late timeout callback do not resurrect private data.
- Deep link/login return, mobile/desktop keyboard and long comments, error recovery without write replay.

### Task 1: Owned review history API
Files: reviews.controller.ts, reviews.module.ts, reviews.service.ts, schema.prisma + migration, reviews.e2e-spec.ts.
Interfaces: GET users/me/reviews response above; reuse existing mutation contracts.
- [ ] Write E2E for auth/validation, per-user pagination, metadata/privacy, eligibility and hidden review deletion. Run tools/test-backend.ps1; expected RED missing endpoint404.
- [ ] Implement query/controller/index. Run PostgreSQL E2E, backend unit/lint/build; expected PASS. Commit and ledger.

### Task 2: Customer history page and state
Files: remote_reviews.dart, review_providers.dart, account/reviews_page.dart, account_navigation.dart, app.dart; test/customer_reviews_test.dart.
Interfaces: OwnerReviewRepository.history(page) -> OwnedReviewPage; ownedReviewsProvider(page). Reuse ReviewEditor and reviewRevisionProvider.
- [ ] Add failing repo/UI tests for paging, own edit/delete including hidden/legacy, retry/empty, safe login, staff isolation, account switch/late read and invalidation. Expected RED missing history/page classes.
- [ ] Implement responsive screen/state, route/nav, reuse mutations. Run focused tests, full Flutter test/analyze; expected PASS. Commit and ledger.

### Task 3: Integration and evidence
Files: tools/verify-reviews-browser.cjs, docs/reviews.md, docs/api.md, docs/progress.md, docs/migration-plan.md.
- [ ] Extend live reviews flow to navigate personal page, verify saved review and edit/delete from it; real Chrome/PostgreSQL expected PASS, inspect375/1440 screenshots.
- [ ] Apply index, restore normal localhost3000 build, restart owned API only, preserve user Flutter. Update docs/evidence and commit.
- [ ] One fresh final review, any Important fixes RED/GREEN + full affected suite, fast-forward and push under existing authorization. Preserve ignored evidence as previously ruled.
