# Persistent browser sessions implementation plan

> Execute inline with executing-plans and test-driven-development under existing
> A-Z authorization. One independent milestone review, one tested fix pass.

**Goal:** Reload preserves customer and staff sign-in without exposing a persistent
credential to JavaScript; logout, password reset and staff changes revoke it.
**Spec:** docs/superpowers/specs/2026-10-21-local-completion-design.md, outcome8.
**BASE:** 4bc7c24. Existing native JSON refresh-token rotation remains compatible.
**Architecture:** Separate browser endpoints and scoped opaque HttpOnly cookies,
hashed in the existing revocable session table; access JWTs remain memory-only.
Flutter web restores both identities before protected screens mount.

## Decisions and constraints

- Compared memory-only (loses reload), JS storage (persistent secret exposed), and
  HttpOnly server sessions. Choose the third. A stable random256-bit browser
  credential has fixed absolute expiry (customer7days, staff8hours); parallel tabs
  and retry after a lost renewal response cannot trigger one-use-token replay.
  Renewing access never rotates/extends the cookie. Login creates a new session
  and revokes the previously presented cookie; privilege/reset revocation already
  covers all sessions. A stolen cookie remains valid until expiry/revocation.
- Add nullable RefreshToken.browserScope restricted to customer/admin; native rows
  remain null. Opaque browser cookies cannot be used as native JWT refresh tokens.
- POST /auth/browser/customer/{register,login,refresh,logout} and
  /auth/browser/admin/{login,refresh,logout}. Responses contain user/accessToken/
  expiresIn only. Names wearly_customer_session / wearly_admin_session; distinct
  matching endpoint Paths, HttpOnly, SameSite=Strict, no Domain. Secure in production
  or HTTPS, local HTTP permitted only on loopback. No secrets in browser storage.
- Every browser endpoint requires exact configured Origin and X-Wearly-Browser:1.
  Production origins must be HTTPS; HTTP browser endpoints only loopback origins
  and loopback Host. Reject missing/null/foreign origin, missing custom header and
  duplicate/malformed cookie. Credentialed CORS has an exact allowlist.
- Browser refresh returns current user; frontend compares identity before retrying
  the original request. Account change clears local state and never retries an old
  user's mutation as the new cookie owner. Native refresh semantics unchanged.
- No Set-Cookie on refresh, including failures, so a stale bootstrap cannot clear
  a later login. Logout revokes the presented session and clears its scoped cookie.
  Login/logout same-client requests must be ordered through actual network
  completion, including a timed-out login response, to avoid late cookie resurrection.
  Concurrent cross-tab explicit login/logout can require re-login; no write may
  cross identities. Cookie Paths isolate scopes, not a same-origin trust boundary.
- Browser startup waits for both restore attempts. 401 means signed out; network
  failure offers retry, preserving cookies. Failed logout remains visibly retryable.
  Nonweb/demo behavior and all existing API clients remain compatible.
- Same hostname for local frontend/API (localhost or127.0.0.1, never mixed).
  Business data only additive migration after verified backup and final review.

## Review focus

1. Cookie CSRF/origin/header validation applies to login/logout as well as renewal;
   no credential in JSON, logs or JS storage. Host/secure behavior cannot silently
   permit nonlocal plain HTTP. Cookie parsing rejects duplicate ambiguity.
2. Parallel renewal and lost response remain usable with bounded absolute lifetime;
   revoked/expired/deactivated/demoted/password-reset sessions fail immediately.
3. Another tab's new cookie must not replay a prior user's pending mutation, nor
   restore stale data after same-client sign-in/out. Late login cannot undo logout.
4. Startup gates private queries; customer/admin cookies and signout are independent;
   transient renewal/logout failures are recoverable without false signout success.

## Task 1: browser session backend

Files: prisma/schema.prisma,migrations/20261022040000_browser_sessions/migration.sql;
modules/auth/auth.service.ts,browser-auth.controller.ts,auth.module.ts;
bootstrap.ts; test/browser-sessions.e2e-spec.ts.

Interfaces: BrowserScope='customer'|'admin'; AuthService register/login optional
browser scope/previous cookie, resumeBrowser(token,scope), logoutBrowser(token,scope).
Cookie response strips refreshToken. Existing access JWT sid uses the same row.

- [x] Write real API tests: cookie flags/safe JSON/hashed storage, missing/foreign
  Origin/header, malformed/duplicate/cross-scope cookie, CORS preflight, parallel
  renewal and stable absolute expiry, old-cookie revocation on login, logout,
  deactivation/demotion/reset revocation, native refresh still rotates. RED404.
- [x] Add migration, regenerate/deploy testDB only. Implement scope-aware issuance,
  current-user recheck under user lock, strict cookie controller and credential CORS.
- [x] Run focused/full E2E, unit, lint/build sequentially. Expected all PASS. Commit.

## Task 2: browser transport, restoration and UI

Files: core/network/{api_client,session_tokens,browser_http_client}.dart;
data/remote_account.dart; app/{api_providers,account_state,app}.dart;
account/admin signout UI; test/browser_session_test.dart and existing session tests.

Interfaces: ApiClient.browserScope optional, browserAuth(action,body?) serialized
through actual transport; SessionTokens.userId optional and nullable refreshToken;
RemoteAccountRepository.restore(); AccountController.restore(); startup FutureProvider.

- [x] Tests for no JS refresh token, shared401 renewal, another user's cookie without
  mutation replay, transient error retry, delayed bootstrap vs login/logout, actual
  network ordering after timeout, startup protected-page gating and logout retry.
  Run before implementation; Expected RED missing browser session support.
- [x] Implement credentialed conditional web client, browser auth transport, identity
  guards and startup/error states. Keep demo/native tests and permissions behavior.
- [x] Focused/full Flutter and analyze. Expected PASS. Commit.

## Task 3: Chrome and local acceptance

Files: tools/test-frontend-api.cjs --sessions,tools/verify-sessions-browser.cjs;
affected existing browser endpoint/reload expectations; docs/BROWSER_SESSIONS_LOCAL.md
and LOCAL_COMPLETION_PROGRESS.md.

- [x] Chrome actual cookies: customer/admin independent login, reload and second tab,
  denied CSRF, no secret in document.cookie/storage, expiry/renewal, logout per scope,
  revocation,375/1440. Update existing staff reload acceptance to persistent login.
- [ ] One independent review then one tested fix pass. Verified business backup,
  migration and original-column fingerprints, compiled read-only smoke. Commit
  guide/ledger and remove only this plan's scratch. Goal remains ACTIVE for AI,
  operations/SEO/providers and final integration.

References checked22October2026: OWASP Session Management and CSRF cheat sheets;
MDN Set-Cookie/CORS. Design choices above are this application's policy.
- https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
- https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie
