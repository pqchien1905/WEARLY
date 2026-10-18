# Wearly storefront refinement implementation plan

> Execute inline using executing-plans. User approved the concrete review recommendations in chat; no further approval gate is needed.

**Goal:** Fix catalog correctness, reduce mobile shopping friction, improve product media presentation and complete supporting routes without changing the Flutter stack or adding backend services.

**Architecture:** Keep repository contracts, Riverpod and shared design tokens. Catalog uses nullable price cap and data-driven facets; mobile filters commit a draft atomically. Quick add owns only selection state and delegates to commerce. Try-On results retain metadata in session, never private photo bytes.

**Spec:** Existing master prompt plus approved review in conversation (16/10/2026).

**Constraints:** Flutter Web/Dart; mock services only; Wearly identity; local assets; no fabricated product photography or real AI claims. Existing workspace has no Git repository; edit in place, no commits/worktrees. No new dependencies required.

## Tasks / ledger

- [x] 1. Catalog: reproduce products over3m missing, then nullable maxPrice; preserve explicit cap query values. Add repository facets from all active products, including Admin-created colors. Tests in refinement_test.dart.
- [x] 2. Mobile filters: draft selections remain open, Apply writes all query parameters/reset page once; dismiss discards; clear resets draft. Price uses single-choice controls. Regression widget tests cover apply/cancel and dynamic colors.
- [x] 3. Quick add: shared bottom sheet with product summary, color/size, current price/stock, pending/error and add-to-cart confirmation. Use existing commerce controller; test actual cart SKU and quantity, unavailable size.
- [x] 4. Product media: add typed gallery media/color associations, thumbnails/keyboard/lightbox and honest fallback for unavailable color photos. Use existing licensed assets; do not depict another garment as an alternative view. Improve crop and catalog photography consistency; document real asset limitation.
- [x] 5. Try-On: compact mobile garment summary and clear current step; session result route /virtual-try-on/:jobId with explicit expired/missing state and delete. Preserve upload privacy/cancellation. Test completed/missing result paths and no photo persistence.
- [x] 6. Supporting pages: Contact demo form with validation/success/no send, FAQ accordions, collection detail routes with curated catalog products and not-found. Footer links. Improve Admin mobile product/inventory summaries/actions while retaining desktop tables. Test interaction and narrow layout.
- [x] 7. Full test/analyze/release, browser shopping/filter/quick-add/support/result flows, updated screenshots; independent final review, docs/acceptance update and preview.

## Review focus

High price SKU must remain discoverable in default/wishlist/Admin/AI catalog reads; custom facet values survive edits; filter dismissal must not change URL; quick add must revalidate stock through commerce; media fallback must never claim a different garment/color is real; private photo bytes must not enter route history/session result stores.

## Rulings

- User authorization covers the review changes. Reuse accepted visual direction; no brainstorming restart or approval pause.
- Actual multi-angle/color photography cannot be inferred from one photo. Build media support and clear missing-photo behavior; disclose any remaining asset gap rather than invent images.


## Completion evidence

147/147 Flutter tests, clean analyzer, release build success. Browser33 checks (9 desktop +6 mobile +7 account +11 refinement), zero errors/external requests. 48 reference screenshots plus interactive states; reviewed mobile quick-add/filter/Admin/Try-On and desktop Contact/curated collection. Gallery infrastructure complete; real multi-angle/per-color assets remain explicitly outstanding. Final independent review addressed with red/green regression. No Git integration applies.
