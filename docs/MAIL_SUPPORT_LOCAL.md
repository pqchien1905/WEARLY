# Local inbox and customer support

Mailpit captures mail on this computer. It does not deliver to external recipients.
Guest contact requests are persisted independently of SMTP availability; administrators
reply under **Hỗ trợ khách hàng** and inspect delivery under **Theo dõi thư**.

## Start the inbox

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mailpit.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mailpit.ps1 status
```

Open http://127.0.0.1:8025. SMTP listens only on127.0.0.1:1025.
The installer pins Mailpit1.31.6 and verifies the official release asset SHA256
before extracting or running it. The runner removes inherited `MP_*` options,
disables remote version checks, and restricts HTTP Host headers to loopback.
No relay, forwarding, webhook, or POP3 service is configured.

The private inbox database is `.tools/mailpit/mailpit.db`; it retains at most500
messages and expires mail after1day. It can contain password-reset links. Do not
commit, publish, or copy it into public static assets. The `stop` command checks
the recorded process executable before stopping it and retains the database.

## API and worker configuration

Set these non-secret options in `backend/.env`, alongside existing secrets:

```dotenv
LOCAL_MAIL_ENABLED=true
PASSWORD_RECOVERY_ENABLED=true
SMTP_HOST=127.0.0.1
SMTP_PORT=1025
SMTP_SECURE=false
SMTP_ALLOW_INSECURE_LOCAL=true
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=store@example.test
PASSWORD_RESET_WEB_URL=http://localhost:5173/#/reset-password
```

Use the actual frontend origin in `PASSWORD_RESET_WEB_URL` and include that origin
in `CORS_ORIGINS`. Start both API and worker after applying the migration and
building the backend. Native commands from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/backend.ps1 run
# In another terminal:
powershell -NoProfile -ExecutionPolicy Bypass -File tools/backend.ps1 worker
```

Local transaction mail refuses production mode or a non-loopback SMTP host.
Password recovery keeps its existing one-use15-minute hashed-token and session
revocation flow; it uses the same inbox, with a separate recovery queue.

## Delivery and support behavior

- Contact accepts guests; only a receipt ID/time is returned. There is no public
  lookup by ticket ID or email. Contact is limited to5requests/minute/IP.
- A retry with the same UUID and content returns the original receipt. Changed
  content under the same key conflicts. The browser keeps uncertain submissions
  frozen across page-component remounts within the current browser session.
- Administrators read requests, reply, close and reopen. Replies check the displayed
  version. A closed request must reopen before another reply. Reply, mail outbox,
  status/version and audit are committed together.
- Order placement, fulfillment, cancellation, carrier return, customer-return
  decision/receipt, explicit COD collection, verified VNPay collection and confirmed
  refunds create immutable mail snapshots in their business transaction.
- Delivery does not imply collection. Receiving returned merchandise does not imply
  a refund. Unverified VNPay/refund outcomes do not send success notifications.
- The worker polls every5seconds, claims up to10rows with a120-second lease, and
  stops after5attempts. Retry delay starts at10seconds and caps at300seconds.
  Raw SMTP error details and reset tokens are not written into mail status/audit.
- Stable Message-ID and Mailpit duplicate-ID suppression reduce duplicate inbox
  entries. SMTP is **at least once** across crashes; a lost SMTP acknowledgement can
  cause a retry. SENT means SMTP accepted the message, not that a person read it.
- FAILED rows stay visible. The durable outbox keeps the record; resetting failed
  delivery is not exposed as a casual one-click action in this milestone.

## Verification

```powershell
node --test tools/mailpit-runtime.test.cjs
node tools/test-frontend-api.cjs --support
node tools/test-frontend-api.cjs --recovery --mailpit
```

Browser acceptance creates only uniquely named synthetic fixtures in the dedicated
`*_test` database and sends only to the native loopback inbox. It never sends mail
to an external service. The existing full backend suite covers failure/backoff,
lease recovery, concurrent claims/replies, transactional rollback and recovery.

During implementation, automatic approval review rejected the combined
stop/restart persistence-check command with `blocked by policy`. Native SMTP
capture is verified; process-restart persistence acceptance remains unverified.

References: [Mailpit installation](https://mailpit.axllent.org/docs/install/),
[runtime options](https://mailpit.axllent.org/docs/configuration/runtime-options/),
[pinned release](https://github.com/axllent/mailpit/releases/tag/v1.31.6).
