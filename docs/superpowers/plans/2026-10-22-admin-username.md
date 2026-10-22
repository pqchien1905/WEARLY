# Admin username login implementation plan

> Execute inline with `executing-plans`; one final independent review.

User specification: admin login uses username `admin` and the supplied local
password, without an email field. Customer login remains email based.

Ruling: work in the clean current feature branch in the user's root workspace,
which serves their running Flutter app. No extra worktree/approval is needed for
this explicitly requested local change. Preserve the owner's user ID, email for
internal relations/recovery, orders and catalog; set the display name to admin.
Do not hardcode a universal password or bypass hashing, roles or session checks.

- [x] Add unique normalized username to User with a generated identifier for
  existing/new accounts; expose it to account and staff views. Admin DTO accepts
  username/password only; customer DTO/registration policy stays unchanged.
  Verify native and cookie login, wrong password, missing/email input, disabled
  users, non-staff rejection and existing session isolation on a test database.
- [x] Change the admin form to username and accept the requested nine-character
  password at login. Send username in the admin request and show username in
  authenticated admin identity. Update affected tests/browser fixtures; verify
  Flutter tests and analyze.
- [x] Apply the additive migration to local business data after private backup,
  set the existing owner's username/name/password, revoke prior sessions/reset
  tokens, restart owned API/worker while preserving the user's Flutter process,
  and verify actual browser sign-in. Record the result and independent review.

Verification ledger:

- Backend RED: new username requests returned 400 before implementation (2 failing,
  1 passing). GREEN: focused username/admin/browser-session/staff tests 33/33.
- Frontend RED: 4 failing/1 passing with the previous admin form. GREEN: focused
  login tests 5/5; full Flutter tests 428 passing, 2 opt-in skips; analyze clean.
- Backend lint/build, 86 unit tests and 53 tool tests passed. Final full E2E:
  `tools/test-backend.ps1 -WithWorker -WithStorage` passed 28 suites, 207 tests.
  The first full run identified an old email-based admin recovery fixture; it
  was updated to username and included in the successful rerun.
- Private business backup captured before migration (42 tables, 42 catalog
  images). No catalog reseed or order reset is part of this change.

- Business migration 28 applied. Hash comparisons verified all preexisting User
  fields and Product/ProductVariant/ProductImage/Inventory/InventoryMovement/
  Order/Payment rows unchanged by migration. Owner ID and internal email retained;
  username/name changed to admin, supplied password stored with Argon2id, old
  sessions revoked and reset tokens consumed in the same audited transaction.
  The first operator attempt rolled back on a PostgreSQL parameter-type conflict;
  separate name/username parameters resolved it, and original hashes were checked
  again before the successful attempt.
- `tools/local.ps1 build` passed. Managed API/worker restarted and both report ready.
  User's Flutter process on 8080 was preserved; managed runtime is intentionally
  partial because it owns only API/worker. No extra web listener was started.
- Live native login returned 201 and protected summary 200. Chrome at widths
  1440 and 375 verified username input, absence of email input, real cookie login
  201, dashboard, reload restoration, HttpOnly cookie and logout. Test used the
  fresh release assets at the existing web origin through Playwright routing,
  with local-network-access permission granted to that test context; actual API
  calls were not mocked. Existing Flutter debug window needs R to load new source.
- One fresh independent review of 7946bdf..d57d8c4 found no Critical/Important
  defects. Its minor documentation ambiguity about customer login for the local
  nine-character password was clarified in the final documentation update.
- Final: Ruling: customer minimum length remains 12; username editing and universal
  seeded credentials remain outside this request. Existing local password choice
  is explicitly authorized. The owner uses the admin page with this password;
  customer sign-in would require a password meeting its separate policy.
- Final: Ruling: keep changes in the current branch/root workspace, preserving
  the user's running development process. No merge/push or separate worktree
  cleanup is needed for the requested local change. Private verification evidence
  and the pre-change backup remain available locally.

Provider approval/Gemini work remains separate. No unresolved blocking findings
or deferred code changes for this admin request.
