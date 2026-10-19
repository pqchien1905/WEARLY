# Reproducible local handoff verification

> Execute inline using executing-plans. User goal remains full handoff readiness; this audit is one gate, not a redefinition of success. No production deployment, data deletion, database reset or secret publication.

**Goal:** Prove migrations and repeatable seed on an empty isolated database, and document the actual supported local workflow and remaining acceptance gaps.
**Architecture:** Add a bounded local verifier using existing Docker PostgreSQL and repository CLI scripts. Create a uniquely named test database and preserve it as evidence. Do not change the application database or environment files. Verify deployed schema against Prisma and verify seed preserves edited records.
**Tech stack:** Node built-ins, existing pg/dotenv, Prisma CLI7 and PostgreSQL17; no packages added.
**Spec:** User active handoff goal; Master Prompt sections5,7,12–14; current PROGRESS.md acceptance table.

## Constraints

- Local Docker PostgreSQL connection from root .env, allow only loopback published port, generated database name wearly_handoff_<timestamp>_<random>_test. Refuse production NODE_ENV; never drop/truncate/reset or reuse a target DB. No secrets in report/console; retain evidence under ignored .tools/handoff.
- Run repository prisma:validate/generate/deploy/seed against only generated DB. Migration status success, all migration names applied, Prisma migrate diff against schema has no changes.
- First seed:32products/256variants/256inventory/32images/4categories/1brand. Make explicit synthetic edits to price/stock/product/category/brand/image and add a synthetic user in new DB only; snapshot all business tables as counts+hashes. Second seed must preserve full snapshots and create no duplicates.
- Keep source/runtime API, existing PostgreSQL databases and user Flutter untouched. Docker runtime startup is local and authorized; no volume removal.
- Update actual handoff report A–H and PROGRESS.md with commands/results and non-claims. Existing tests are evidence only for their covered behavior.

## Review focus

- Verifier target isolation and accidental credentials/log output; interrupted runs preserve data and can be diagnosed.
- Migration/schema drift and seed changing mutable records on second run.
- Assumptions about Docker/native ports, role permissions and tool availability in setup instructions.
- Honest separation of demo, implemented remote features and external-provider/production work.

### Task 1: Isolated bootstrap verification
Files: tools/verify-bootstrap.cjs, bounded evidence in .tools/handoff, optional targeted fixes only if actual failures prove necessary.
- [x] Implement verifier with target guards and runtime assertions; this is a verification tool, not new product behavior. Test guard refusal with invalid configuration before DB mutation.
- [x] Run against fresh local DB; inspect migration/schema/seed evidence. If product failure appears, reproduce before fixing and run affected suite. Expected: drift-free migrations, exact seed counts, preserved snapshots.

### Task 2: Handoff audit and integration
Files: docs/backend-report.md or dedicated current report, docs/setup.md, README.md, PROGRESS.md.
- [x] Read actual controllers/config/diagrams/files and classify each Master Prompt acceptance item with current evidence; keep missing/unverified items explicit.
- [x] Verify Docker API/worker build/runtime in isolated local infrastructure if feasible; otherwise preserve precise remaining gate and continue independently useful work.
- [x] Run final read-only review of changes, address Important findings once with appropriate regression evidence, integrate under prior authorization. Do not mark overall goal complete until all required gates are proved.

Completed on main through238746c. Final review:2 Important cleanup findings fixed in one pass with5 RED→GREEN regression tests and successful real Docker rerun;1 Minor deferred (synthetic UPDATE row-count assertions). Evidence and remaining limits: docs/handoff.md, PROGRESS.md. No databases, volumes or scratch evidence deleted.
