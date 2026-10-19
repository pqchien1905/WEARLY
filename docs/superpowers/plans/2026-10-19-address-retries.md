# Safe address creation retries implementation plan

> Execute inline using executing-plans, TDD, one fresh final review. User explicitly requests autonomous completion; preserve existing data and never deploy production.

**Goal:** A lost create-address response or failed follow-up read cannot turn Retry into duplicate addresses.
**Architecture:** Extend UsersService and existing account repository/editor. Optional Idempotency-Key preserves compatibility; a per-user durable create receipt binds a key to a canonical payload hash and address. Flutter keeps one key and exact payload for an unresolved form submission.
**Tech stack:** existing NestJS/Prisma/PostgreSQL and Flutter/Riverpod; no new packages.
**Spec:** User's active handoff goal plus the verified duplicate-address finding in docs/progress.md. Existing address CRUD/UI stays intact.

## Global constraints

- No destructive migration or data reset. Add AddressCreateReceipt with composite PK(userId,key), requestHash SHA256, nullable unique addressId FK SET NULL, createdAt; User cascade only on normal user deletion. Keep receipt when address is removed so retry returns410 without resurrection.
- POST users/me/addresses accepts optional Idempotency-Key /^[A-Za-z0-9_-]{16,128}$/; absent retains legacy behavior. Same user/key/same normalized payload returns current address, changed payload409. Different users isolated. Same transaction/user lock covers receipt/default changes/create. Replay must not reset current default or overwrite edits.
- Flutter saveAddress adds optional creationKey to existing interface, editor generates random48hex once per create form. Repository snapshots POST payload (including first-address default decision) for that key until confirmed full read. Same-key retry uses exact payload; changed input while pending must be rejected, never silently discarded. Definite400 releases snapshot for correction; uncertain result retains it.
- Editor freezes inputs after uncertain save, exposes retry of same submission and close/reload guidance. Errors remain explicit; logout/old session guards remain. Demo remains working; no second state architecture.
- Late completion after timeout invalidates account cache only in same session. Retrying is user initiated, never automatic.

## Review focus

- Same-key concurrent requests, payload mismatch, cross-user keys, edited/deleted address replay and defaults.
- First-address default decision remains identical on retry after response loss; post-write read failure does not duplicate.
- Input/session changes during requests, repeated retries, demo behavior, late completion invalidation.
- Additive migration and endpoint backward compatibility; no secret/PII receipts or logs.

### Task 1: Durable API receipt
Files: prisma schema/additive migration, users.service/controller, address retry E2E.
- [ ] Write actual PostgreSQL replay/race/payload/deletion/ownership/header tests, run expected RED duplicate/missing conflict.
- [ ] Implement receipt/transaction/validation; generate+migrate test DB. Full backend unit/E2E/lint/build PASS. Commit.

### Task 2: Flutter recovery and handoff record
Files: account_details domain/interface, mock/remote repository, controller, address editor, focused repository/widget tests, API/database/progress docs.
- [ ] RED tests for same key/body after committed-but-lost reply, post-read failure, UI frozen draft/retry, old session. Implement minimal guarded recovery.
- [ ] Full Flutter/analyze, live shopping, normal release build PASS. Deploy only additive native migration; update PROGRESS.md and docs.
- [ ] Fresh whole-branch review; one Important fix pass if needed, record rulings, commit/integrate under existing authorization. Preserve evidence.
