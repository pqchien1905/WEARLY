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
- [ ] Apply the additive migration to local business data after private backup,
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

Local application and independent review: pending. Provider approval/Gemini
work remains separate.
