# Local mail and customer support implementation plan

> Execute inline with executing-plans and TDD; one independent final review.

**Goal:** Run a persistent loopback inbox, deliver recovery/order/support messages
locally, and replace the contact demo with durable support requests and staff replies.
**Architecture:** Mailpit native Windows binary; transactional PostgreSQL mail outbox
and bounded worker; public create-only contact API and authenticated admin workflow.
**Tech stack:** Existing NestJS/Prisma/Nodemailer/Flutter, Mailpit1.31.6.
**Spec:** docs/superpowers/specs/2026-10-21-local-completion-design.md.
**BASE:** 61d1a8c.

## Global constraints and decisions

- User local-only: bind inbox HTTP127.0.0.1:8025 and SMTP127.0.0.1:1025; no relay or
  forwarding. Mailpit retains messages in private .tools/mailpit/mailpit.db, max500
  messages/1day. Strip inherited MP_* settings before launch. Windows hidden process.
- Pin official Mailpit1.31.6 windows-amd64 ZIP, SHA256
  5d5ad094bfb3bac9004f9d1105d2335fea9f8952c09951df73ae0a280e34d3b1
  from GitHub release asset digest. Validate before extract/start; no source execution.
- LOCAL_MAIL_ENABLED false by default; true requires non-production, loopback SMTP,
  existing explicit insecure-local SMTP permission/from address. Recovery continues
  to use its queue/token lifecycle and same inbox; enable it in local environment.
- Outbox records email text in the transaction that changes commerce/support state.
  Unique event key, immutable recipient/subject/body. No raw errors, tokens or secrets
  in logs. Recovery links remain only in the designated inbox and existing token flow.
- Worker5s polling, batch10, claims with PostgreSQL row lock/SKIP LOCKED, lease120s,
  bounded SMTP calls, maximum5attempts, backoff capped300s. Stable Message-ID. SMTP
  delivery is at-least-once across crashes; do not promise exactly-once external mail.
  SENT rows retained; no silent deletion of support requests. Failed rows visible.
- Notification events: order placed, fulfillment status, cancel, carrier returned,
  customer return decision/receipt, COD collection, verified VNPay payment and refund
  success. Each event key includes immutable event/receipt ID or order version.
  Never label delivery as payment or physical return as refund.
- Contact supports guests: POST /support, UUID requestKey, name2–100,email<=254,
  message10–3000,5/min rate limit. Normalize email; freeze payload on uncertain retry.
  Response is receipt{id,createdAt}; no public list/detail lookup or email-based
  ownership inference. Guests receive staff response in local inbox.
- Admin list/detail, versioned OPEN/ANSWERED/CLOSED state, replies3–3000chars with
  UUID key; reply atomically writes Reply+outbox+audit+version. Replay canonical,
  changed payload/version conflict409. Closed ticket must reopen before reply.
- Existing demo mode remains explicitly simulated. Remote contact only claims
  receipt after successful persistence; no claim of external delivery.

## Review focus

1. Crash between business commit and mail transport: outbox survives; retry does
   not create duplicate event rows (DB/API test).
2. Parallel workers and stale leases: only owner of lease completes a claimed row,
   shutdown bounded, no stuck processing forever (real SMTP/DB worker tests).
3. Guest retries/forged email/support ID: public API never exposes stored messages,
   admin authorization and replay hash checked (API test).
4. Staff reply version conflict or audit failure: no orphan mail/partial reply;
   external SMTP unavailable never rolls back an already accepted request (API test).
5. Inbox cannot inherit relay/forwarding settings; all listener addresses loopback;
   frontend shows stored receipt versus delivery status honestly (tool/UI tests).

## Task 1: native inbox and bounded transport

Files tools/mailpit.ps1, tools/mailpit-runtime.cjs and tools/mailpit-runtime.test.cjs;
backend/src/modules/mail/mail-transport.ts, test/mail-transport.spec.ts; setup docs.
Runtime exports buildOptions(binary,folder,env) with loopback args, private DB path,
filtered environment. SMTP helper shares existing secure/no-URL/file-access settings.

- [x] Tests RED for loopback binds, no inherited forwarding/relay and required
  config/bounded transport; implement minimal helper and pinned installer/start/status.
- [x] Verify SHA and binary version, start locally, send synthetic SMTP and read
  via Mailpit API. No messages to external mail systems. Process-restart check was
  blocked by automatic approval review; limitation recorded in guide and ledger.

## Task 2: transactional outbox and persistent support API

Files schema/migration; modules/mail/outbox.ts, mail.service/module.ts;
worker/mail.worker.ts; modules/support DTO/controller/service/module;
order/payment/return/shipment services notification hooks; test/mail-support.e2e-spec.ts.
Outbox has eventKey, recipient, subject, body, statusPENDING/PROCESSING/SENT/FAILED,
attempts, leaseToken/leaseUntil, nextAttemptAt, sentAt, safe lastError and timestamps;
optional orderId/supportId FK for scoped lifecycle. SupportTicket holds immutable
initial content/hash/key, status/version; SupportReply holds actor/message/key/hash.

- [x] API/realDB+SMTP tests RED for idempotency, auth, bounded payloads, concurrent
  replies, rollback, mail failure/retry/lease, immutable event facts and status.
- [x] Add migration/testDB; implement claim+send+settle with lease ownership and
  lifecycle-safe polling. Record outbox in authorized transactions. Expose admin
  mail status/counts without recovery tokens; no inbox public API in application.
- [x] Backend full E2E/unit/lint/build GREEN; native recovery smoke uses real local
  inbox link, expiry/consumption and old-session invalidation remain verified.

## Task 3: contact/admin UI and acceptance

Files frontend remote_support.dart/providers; info/support_pages.dart;
admin remote support page/navigation and mail status; tests/support_test.dart;
tools browser --support acceptance.

- [x] Tests RED for frozen contact retry/remount, honest receipt, admin reply/status,
  version conflict and mail pending/failure visibility; implement with existing UI.
- [x] Chrome guest submission -> admin reply -> local inbox message, order status
  notification, mobile/desktop/reload. Full Flutter/analyze GREEN.
- [x] Independent review once, important fixes RED->GREEN; backup/migrate/fingerprint/
  compiled smoke, local configuration guide and durable ledger; commit.

Official references: https://mailpit.axllent.org/docs/install/ ;
https://mailpit.axllent.org/docs/configuration/runtime-options/ ;
https://github.com/axllent/mailpit/releases/tag/v1.31.6 .
