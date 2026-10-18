# Final code review — 2026-10-18

Independent read-only review of the implemented backend, Flutter adapter, migrations and setup helpers found no Critical/Important blocker in the commerce paths.

Resolved during review:

- Extreme order subtotal + express fee could exceed Decimal(14,0): now400 before stock mutation. Regression failed with500 before the fix, then passed.
- Optional DTO fields accepted null and reached nonnullable Prisma fields: validators now skip only undefined; PartialType uses skipNullProperties=false. Profile/address null regression failed with500, then passed with400.
- PowerShell test helper left DATABASE_URL/TEST_DATABASE_URL/NODE_ENV in caller environment: finally restores previous values. Real helper run reports Environment restored=True and10 passing E2E.

Not judged as complete: Docker/Redis/worker runtime pending Windows reboot, upload/provider/payment lifecycle, production hardening, native mobile builds. Credentials were not read by the reviewer. These are scope and environment limits, not passed acceptance checks.

Final unit/build/lint and relevant PostgreSQL tests were rerun after fixes. Production dependency audit has0 findings.

## Native runtime follow-up review

An independent read-only review of the continuation found no Critical/Important production issue. The initially selected reviewer was unavailable at capacity; the fallback reviewer completed the review.

All three test reliability findings were addressed:

- Provider state is explicit in success/privacy tests. Running the replay test by itself first reproduced a failure; it now passes independently.
- Replay assertions wait until the reset outbox event is actually published again.
- A PostgreSQL advisory lock rejects overlapping worker suites on the same test database. Preflight rejects unfinished AI fixtures before worker startup, rather than processing another run's rows. A competing-suite check confirmed no new AIJob was inserted.

After fixes: unit5, commerce10 + worker6 E2E, lint passed; the production build passed after the provider-error fix. Flutter live catalog passed against native PostgreSQL17.11. Provider errors are sanitized in both PostgreSQL and Redis. Paid AI and storage test doubles are confined to tests.

Host installation/permissions/pgAdmin/readiness were verified independently by the implementing agent, not the read-only reviewer. Docker/Linux Redis/container builds remain unverified because Windows has a pending repair restart. Real AI/uploads/payment and mobile builds remain outside the completed foundation scope. Existing BullMQ installations must retain their previous prefix until drained; this local installation had no previous real queued jobs.
