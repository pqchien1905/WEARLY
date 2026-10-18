# Separate admin and customer sign-in

> Use executing-plans inline; one fresh final review. User explicitly requests separate customer/admin login interfaces and usage.

**Goal:** `/login` serves shoppers; `/admin/login` serves authorized staff. Each area owns its session and logging out of one leaves the other intact.
**Architecture:** Separate admin tokens/client/account providers, reused account controller with explicit session configuration, server-side ADMIN-only login endpoint. GoRouter protects admin deep links and preserves a safe internal admin return path. Existing demo behavior remains clearly labelled.
**Stack:** Existing Flutter/Riverpod/go_router and NestJS/PostgreSQL. No dependencies or schema migration.
**Spec:** User's current separation request; existing `docs/admin.md` and account/session contracts.

## Design direction

Palette: canvas #F7F8F7, surface #FFFFFF, ink #252329, plum #65394D, soft plum #ECE5E9, muted #67636A. Keep Manrope for headings/wordmark and BeVietnamPro for form/body.
Customer retains its fashion image and storefront chrome; label the form explicitly for customers. Admin uses an uninterrupted plum identity column beside a quiet white form, left aligned, with no shop navigation, cart, registration or newsletter. On mobile the identity column becomes a compact header and the form remains scrollable. No invented statistics or technical token/storage text in the form.

```text
Customer: [shop header] [fashion image | customer form] [shop footer]
Admin:    [plum WEARLY Studio identity | admin form + customer-login link]
Mobile:   [compact studio header] [admin form] [customer-login link]
```

## Constraints and review focus

- Independent login/logout/refresh/expired-session behavior, including late responses and open dialogs.
- Customer credentials must be rejected by admin login before issuing a session; all admin data requests remain server-authorized.
- Existing admin user may sign into customer area separately unless user requests stricter account-role separation; never grant privileges via public registration.
- Admin `next` only allows internal admin pages, excluding its login route; customer `next` never enters admin routes. No external/protocol-relative/backslash redirect.
- No customer API requests caused solely by admin login; no storefront chrome in admin login or unauthenticated admin pages.
- Keyboard validation/password visibility, long emails and 375/1440px layouts stay usable. Demo remains explicit.

### Task 1: Independent session contracts
Files: backend auth controller/service, `backend/test/admin.e2e-spec.ts`; frontend api/account providers, remote account repository; new `frontend/test/separate_sessions_test.dart`.
- [ ] RED: `/auth/admin/login` rejects CUSTOMER without issuing tokens, accepts ADMIN, independent sessions survive counterpart logout. Flutter providers preserve separate identities and reject late admin responses.
- [ ] Implement ADMIN-only server login and separate provider/client/token instances. Run backend E2E/build/lint and focused Flutter tests; expected PASS.
- [ ] Commit session contracts.

### Task 2: Separate login experiences and route protection
Files: new admin_login_page.dart, app router/gate, admin shell/providers/dialogs, account page/footer, UI tests.
- [ ] RED: admin deep link opens standalone admin form, customer login cannot unlock it, sign-in returns to correct admin path, logout isolates sessions, unsafe next values fall back, mobile has no overflow.
- [ ] Implement visual separation and route/session wiring; update existing admin tests to use dedicated admin session. Run Flutter analyzer/full suite; expected PASS.
- [ ] Commit interfaces and routing.

### Task 3: Browser verification, docs and integration
Files: real admin browser helper, README, admin/API/progress docs.
- [ ] Exercise separate forms, wrong-role rejection, simultaneous identities and independent logout through real PostgreSQL/Chrome, plus existing admin mutations.
- [ ] Inspect 375/1440 screenshots, build normal localhost3000 release; update short commands/URLs.
- [ ] Fresh independent review, fix important findings with regression tests, integrate/push authorized repository.
