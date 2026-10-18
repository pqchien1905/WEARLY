# Flutter API shopping implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline, task by task. Steps use checkbox syntax for tracking.

**Goal:** Complete a real customer journey in the existing Flutter Web UI: register/login, profile/addresses, SKU cart, COD checkout, persisted order history and cancellation.

**Architecture:** Retain Riverpod, routing, domain models and visual layout. A shared in-memory session and ApiClient back remote repositories selected together with USE_REMOTE_API=true; existing demo and catalog-only flags remain available. Async cache-backed commerce preserves the current UI contracts while exposing loading/error/retry and session isolation.

**Tech Stack:** Existing Flutter/Dart/http/Riverpod, NestJS REST /api/v1, Prisma7/PostgreSQL. No new state framework or browser token persistence.

**Spec:** User master prompt (backend foundations, Flutter integration, ownership and real API contracts), docs/migration-plan.md, docs/api.md, and the user's instruction to continue after the status audit. Implementation choices below belong to the agent.

## Global constraints

- Preserve Flutter UI, navigation, mock mode and the F12/PageStorage fix.
- Web tokens stay in RAM; reload requires login again. Persisted account data is fetched again from PostgreSQL after login.
- Never fall back to mock after an API error. No simulated payment success or AI results in the API shopping workflow.
- New runtime feature flag USE_REMOTE_API enables catalog and all implemented customer repositories. API_BASE_URL remains environment configuration.
- Server owns prices, inventory, totals and authorization. Checkout sends addressId, expectedSubtotal, cartVersion and a stable Idempotency-Key.
- Unsupported remote wishlist/style/password reset/admin/AI functions must disclose unavailability; no fabricated save success. Full admin integration and external providers remain a separate stage.
- Reuse the existing Windows native backend. Tests write synthetic data only to the dedicated wearly_test database; no reset/drop of user databases.

## Review focus

- Concurrent401 responses must share one refresh; a late response must not log out or overwrite a newer user.
- Logout/account switch must discard cached personal data and reject delayed mutations/refresh completion.
- Checkout timeout/retry must retain its idempotency key and exact request; no duplicate purchase or stale stock consumption.
- Address edits, deletion and profile JSON must map real IDs/defaults and nullable backend fields without inventing saved data.
- Loading/error states must distinguish unknown data from an empty cart/history; mobile layout and demo regression tests remain green.

### Task 1: Shared session and authenticated transport

**Files:** core/network/session_tokens.dart, api_client.dart; new app/api_providers.dart, data/remote_account.dart, test/remote_session_test.dart; domain/account.dart, app/config.dart, app/account_state.dart, app/providers.dart.
**Interfaces:** ApiClient.request(method,path,{query,body,headers,authenticated,refresh}) returns Future<Object?>; SessionTokens tracks session generation and token rotation separately; RemoteAccountRepository implements AccountRepository. UserProfile gains optional id and role. apiClientProvider/sessionTokensProvider/remoteApiProvider are shared.
- [x] RED: tests for concurrent refresh, late401/session switch, logout versus pending login/refresh, profile mapping, failed login and unavailable reset.
- [x] Implement request guards, one refresh/retry, memory-only session clear notifications and real auth repository; keep public calls independent of auth retries.
- [x] Run targeted tests, existing remote catalog and account regressions; commit.

### Task 2: Profile and addresses

**Files:** new data/remote_account_details.dart, test/remote_account_details_test.dart; app/account_details.dart; features/account/account_page.dart, address_page.dart, account_navigation.dart.
**Interfaces:** RemoteAccountDetailsRepository(ApiClient) implements existing AccountDetailsRepository; maps address UUID/default and calls GET/POST/PATCH/DELETE users/me/addresses. Unsupported style save throws a useful ApiException.
- [x] RED: round-trip Vietnamese address fields/default, update/delete errors, nullable profile phone, real UI validation and identity-switch late-result guard.
- [x] Wire repositories and mode-appropriate account/address copy; retain layout and mock labels in demo. Password registration follows API12..128, profile save only supported name/phone fields.
- [x] Run focused tests and commit.

### Task 3: Cart and order repositories

**Files:** domain/commerce.dart, app/commerce_state.dart, data/mock_commerce.dart; new data/remote_commerce.dart, test/remote_commerce_test.dart.
**Interfaces:** CartRepository.remove/clear and OrderRepository.setStatus become FutureOr<void> to preserve synchronous mock behavior; remote implementations return Future<void>. Cached remote repositories expose refresh/dispose methods, cart version/item UUIDs, paginated order loading and owned detail loading. CheckoutDraft gains optional addressId. CommerceController awaits async mutations and exposes loading/error/retry.
- [x] RED: server monetary strings/UUID mapping, mutations serialized, failed removal retains cache, auth change prevents late data, paginated orders, pending cancellation, timeout retry uses identical idempotency key/body, successful retry clears cart exactly once.
- [x] Implement real adapters, bounded validation, server snapshots/status mapping and session-bound cache lifecycle; no local stock mutation.
- [x] Run adapter/controller and existing commerce tests; commit.

### Task 4: Customer UI integration

**Files:** cart_page.dart, checkout_page.dart, orders_page.dart, account_navigation.dart, app/app.dart, core/widgets/store_shell.dart, relevant feature guards; test/remote_shopping_test.dart.
**Interfaces:** Existing routes and widgets consume the shared providers. Explicit login gate for private pages, pending/error/retry states for API data, saved address selection and COD checkout, persisted order details/cancel.
- [x] RED: widget journey login/address/cart/order/cancel using controlled HTTP responses; failed checkout actionable; signout clears data; remote unavailable features cannot claim saved/purchased data.
- [x] Preserve layouts while changing data wiring and copy. Avoid demo notices on real saved account/order flows; COD remains unpaid. Guard unsupported remote admin/AI/style paths clearly.
- [x] Run widget tests and whole Flutter suite; commit.

### Task 5: Live verification and handoff

**Files:** tools/frontend.ps1, docs/setup.md, migration-plan.md, progress.md; new frontend/test/live_shopping_test.dart and bounded tools helper if required.
**Interfaces:** Frontend helper action api starts Flutter with USE_REMOTE_API and configured local base URL. Live test is opt-in against a dedicated test API/database.
- [x] Run live register/login/profile/address/cart/COD/order history/cancel/logout against NestJS + real PostgreSQL test DB, including a new client login restoring persisted data.
- [x] Run analyze, full Flutter tests, Web release build, relevant backend E2E if backend changed, and Chrome mobile/desktop checks.
- [x] Request one independent final review; fix findings with regression tests, update docs/status honestly, integrate and push under existing authorization.

