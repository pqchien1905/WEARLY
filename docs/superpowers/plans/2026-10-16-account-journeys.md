# Account and shopping continuity implementation plan

> Execute inline with executing-plans. User requests finding and implementing missing interface features; existing design/Flutter/mock constraints remain authoritative.

**Goal:** Complete the gaps between account, checkout, orders and fashion AI without adding real services.
**Architecture:** Add typed AccountDetailsRepository and account-scoped AsyncNotifier; reuse commerce and metadata-only Try-On registry. Separate account navigation, address/style pages and order views from existing auth/profile code.
**Tech stack:** Existing Flutter Web, Dart, Riverpod, go_router. No new packages.
**Spec:** fashion_ai_commerce_agent_spec (1).md II.1/orders/style_profiles/addresses; frontend Master Prompt 5.C/E/F/G, existing MASTER.md.

## Audit and decisions

Present: shopping/search/filter/cart/checkout; authentication/profile; order list/detail; AI mock; result detail; Admin CRUD and status/filter/search. Missing or shallow: reusable delivery addresses, explicit saved style preferences, discoverable result history, customer order filtering and progress, contextual product-to-Stylist entry. These form this implementation scope.

Out of scope: actual reviews/refunds/shipping tracking/payment/RBAC, coupon calculation, real product photography and backend. Do not imply the original broad specification is production-complete.

Design remains canvas #F7F8F7, white #FFFFFF, ink #252329, muted #67636A, accent #65394D, soft #ECE5E9. Manrope headings / Be Vietnam Pro UI. Account subnav wraps into rows on mobile; restrained address blocks with default/edit/delete actions. Order progress communicates current stage, not fabricated timestamps. Existing full-width shell, bounded forms, shared motion.

## Tasks

- [x] 1. Add domain/account_details.dart (DeliveryAddress, StylePreferences, AccountDetails, AccountDetailsRepository), data/mock_account_details.dart and app/account_details.dart. Async read/save/delete/default/style; max5 addresses; first default, deletion chooses a remaining default. Reset on signout/account identity change. Tests: CRUD/default, validation/cap, failed write unchanged, stale completion after signout never restores data.
- [x] 2. Add account_navigation.dart, address_page.dart, style_page.dart and routes /account/addresses,/account/style. Reuse existing fields/buttons/error/retry/loading. Save/update/delete/default with confirmation and real feedback. Checkout gets explicit saved-address picker that fills editable recipient/phone/address/email only on user action. Tests: validation, selection preserves manual edits, empty/login states, responsive320/375/768/1440.
- [x] 3. Split OrdersPage to orders_page.dart; customer search/status filters and date/status/amount hierarchy; shared OrderProgress uses current status only, cancellation/unknown statuses handled honestly; detail recipient contacts, SKU/quantity/price and back/help actions. Tests: status filtering, unknown ID, long product names at150%, Admin status reflected immediately.
- [x] 4. Add /account/try-ons history using existing bounded metadata registry, open/remove/clear confirmation; links from account and room/result pages. Add style preferences apply button to Stylist, controlled keyed dropdowns; add product context prompt CTA. Tests: real preference fields applied, history delete invalidates URL, no personal image storage, contextual prompt reaches editor.
- [x] 5. Run full tests/analyzer/build, browser end-to-end additions, screenshots mobile/desktop, independent read-only review, update contracts/acceptance/report/README.

## Review focus

- Old async save completes after signout/reset: repository scope + completion generation must prevent reappearance (task1).
- Removing default/last address: preserve exactly one valid default or none; checkout does not overwrite typing (tasks1/2).
- A page enters directly signed out: navigation and clear login/demo state remain usable (task2).
- Order cancelled/unknown status: no fictional completion or timestamp (task3).
- Deleted/missing Try-On product/result: route handles empty state, only job/garment metadata retained (task4).

No Git repository: changes in place, no commits/worktrees. Broader extension choices above are implementation rulings under the user's request to identify and fill gaps.
