# Password recovery

Grounding: existing `/forgot-password` route and AccountRepository contract are
disabled in API mode; the audit identifies recovery as High. Keep Nest/Prisma,
BullMQ worker, Argon2 and Flutter session architecture.

## Design

- Recovery disabled by default. Enabling requires explicit SMTP configuration
  and a trusted reset-page URL, HTTPS outside local development. No mail is
  sent externally during implementation; tests use a loopback SMTP receiver.
- Public request endpoint queues every syntactically valid email, with the same
  accepted response. Account lookup and SMTP run in the worker so mail/network
  latency does not disclose account existence in the HTTP response.
- Per-IP throttling and Redis deduplication per normalized email (HMAC ID,
  60-second TTL). Queue failure returns a sanitized unavailable error.
- Worker uses random 256-bit reset tokens, stores only SHA256, expiry15minutes,
  and sends the token in the configured frontend URL fragment. SMTP uses TLS,
  timeouts, no debug/body logging and no file/URL attachments.
- No user state/session changes on requesting recovery. Failed delivery revokes
  that attempt's token; bounded retries may issue another token. Job payload
  contains email, never password or raw token; completed jobs removed and failed
  records bounded. Email delivery beyond SMTP acceptance remains unverified.
- Reset atomically consumes a valid token, changes password, invalidates all
  reset tokens and sessions. Concurrent reset/refresh/login must not restore a
  session authenticated with the previous password. Queued older requests must
  not issue tokens after a completed reset.
- Immutable request cutoff uses `clock_timestamp()` (timestamptz) before
  enqueue and User.passwordChangedAt written from the same DB clock during
  reset. Every retry checks the original requestedAt under the user lock.
  The cutoff is null until first reset. Login rereads hash/role/active under
  that lock after password verification.
- Producer commands are bounded; shutdown force-disconnects after a failed
  graceful close. SMTP runs outside the retryable token transaction and
  BullMQ receives only fixed failure codes. Post-reset notification is best
  effort and contains no token/password.
- UI request message does not reveal account existence. Reset requires password
  confirmation, handles invalid/expired links, clears local sessions and returns
  to login without automatic authentication. No demo success in API mode.
- Reset route strips token before page/storage keys; uncertain responses
  discard the form token. Invalidation captures session generations so late
  responses cannot clear a subsequent login.

## Verification

Regression-first API, configuration and session race tests; real PostgreSQL,
Redis and SMTP loopback delivery; one-use/expiry/inactive user/wrong token;
mail failure sanitization; Flutter request/reset/session/error tests and Chrome
journey with actual received mail. Build/lint/audits, migrations/container and
recovery checks, independent security review before handoff.

References: [OWASP recovery guidance](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html),
[Nodemailer SMTP options](https://nodemailer.com/smtp),
[BullMQ TTL deduplication](https://docs.bullmq.io/guide/jobs/deduplication).
These inform security implementation, not store business policies.
