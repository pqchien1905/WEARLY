# Local operations and verification

Implements outcome9 of `2026-10-21-local-completion-design.md` in two milestones:
runtime/monitoring/CI first, then independently verified backup/restore. Existing
local-only A-Z authorization applies. Keep Node24, Flutter3.47.7, NestJS, native
PostgreSQL17, Redis/Memurai, MinIO and Mailpit; do not switch platform or deploy.

## Runtime and monitoring

- An ADMIN-only operations view shows database/schema, Redis, private storage,
  worker heartbeat, local mail availability and provider configuration, plus
  pending/failed work counts and AI estimates. Unknown/unavailable is distinct
  from zero. No customer identifiers, photos, request bodies, raw exceptions,
  database URLs or credentials appear in diagnostics. No paid retry action.
- Heartbeat proves that the worker process is alive, not that a particular job
  succeeded. Queue/outbox age and terminal failure summaries expose stalled work.
  Probe timeouts must close their transports and never occupy the business pool.
- Native scripts build and start compiled API/worker/web on loopback, report
  readiness and stop only children they created and can authenticate. PID reuse,
  stale files, occupied ports and partial starts must not stop unrelated programs.
  Keep existing PostgreSQL/Memurai/MinIO/Mailpit services alive. Do not retry the
  previously blocked Mailpit restart acceptance under another helper.
- Default browser origin is http://localhost:8080 and API localhost:3000. Runtime
  children get matching local CORS/recovery-link settings; secrets remain in
  backend/.env. Environment files are not overwritten. No implicit migrations,
  seed, provider calls, process-wide kills or external network exposure on start.
- CI runs locked dependency installation, lint/build/unit/integration and Flutter
  analysis/tests using dedicated synthetic services and disabled external providers.
  Local acceptance commands remain executable independently. Workflow creation
  does not imply a hosted run has occurred or authorize pushing the repository.

## Recovery milestone remains required

Prepare a separate plan for native consistent database archives, managed catalog
objects and restoration into fresh retained targets. Never overwrite/drop a
database or reuse a target bucket. Verify checksums and restored schema/data.
Specify how ephemeral private AI images, sessions, recovery tokens and pending
paid work are treated before implementing restore; do not silently restore revoked
credentials or repeat externally accepted work. Existing Docker-only synthetic
recovery checks do not satisfy native business recovery acceptance.

Public deployment/TLS/off-host production backup remain outside local scope.
Store identity/policies/SEO and final root integration follow these milestones.
