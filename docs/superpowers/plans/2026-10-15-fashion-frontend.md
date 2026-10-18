# Fashion Frontend Implementation Plan

> Execute inline with executing-plans. User explicitly authorizes implementation and autonomous concept choice.

**Goal:** Flutter Web fashion storefront, mock AI, account and admin with one design system.
**Architecture:** Feature-first Flutter app, two shells, domain models and async repository interfaces, Riverpod dependency injection, URL query routing.
**Tech Stack:** Flutter/Dart, flutter_riverpod, go_router, file_selector, flutter_test.
**Spec:** `fashion_ai_flutter_frontend_anthropic_frontend_design_prompt.md`, `fashion_ai_commerce_agent_spec (1).md`, `design-system/fashion-ai-commerce/MASTER.md`.

## Global constraints

Flutter only; no real backend/AI/payment. Vietnamese. Mock disclosure. No images leave client. Complete three reference screens before expanding. All catalog/cart/AI/admin read one repository.

## Review focus

1. Product variant stock can change after cart add: checkout revalidates, no silent oversell.
2. URL query/back must restore filters, including Vietnamese search and empty result.
3. Narrow/large text viewport must not overflow or obscure CTA.
4. Deleting/cancelling a running try-on must not revive image/result on delayed completion.
5. Admin edits must update storefront and preserve old order snapshots.

## Tasks

- [ ] P0 Foundation: documents, local SDK, fonts/imagery; tokens/theme and gallery; Product/Variant/Money/ProductQuery + ProductRepository interfaces. Unit tests for query, SKU/stock consistency. Home/Catalog/Detail with shared grid/gallery/selector; widget tests and screenshots before expansion.
- [ ] P1 Shopping: CartRepository add/update, OrderRepository checkout; unit tests for stock clamp, totals, immutable snapshots; search suggestions, URL filters, wishlist, cart drawer/page, checkout validation and confirmation. Widget shopping flow.
- [ ] P2 AI: StylistRepository deterministic catalog recommendations, async statuses and errors; TryOnRepository stream statuses and cancellation. Test recommendation constraints, consent, invalid file, cancel/delete races. Upload in memory only, explicit illustrative result.
- [ ] P3 Account/admin: demo auth/profile/orders/wishlist, separate admin shell, product CRUD/variants/stock/orders/promotions/content/monitoring/settings with validation. Test persistence and shared source updates.
- [ ] P4 Audit: analyze, full tests, release web build, Chrome screenshots 375/768/1024/1440 and mobile smoke. Visual critique/fix, contracts/readme/acceptance with honest Pass/Fail/Not tested.

## Verification commands

From apps/storefront: `flutter analyze`, `flutter test`, `flutter build web --release`. Browser automation script in `tools/` writes screenshots and records routes/viewports. Store logs in `docs/qa/`. Each milestone report in `docs/milestones.md`.
