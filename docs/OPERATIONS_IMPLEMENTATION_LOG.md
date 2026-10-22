# SDD ledger — docs/superpowers/plans/2026-10-22-local-operations.md

Milestone BASEf649201, plan commita75bada. Task1 brief read, BASEa75bada.
Existing local/A-Z authorization and spec apply. Execute inline, one whole-milestone
independent reviewer only at final checkpoint. No implementation subagents.
Pre-flight: probes snapshot -> remote_operations DTO -> browser diagnostic fixture
align; heartbeat consumed by snapshot and native runtime acceptance. Runtime uses
current compiled backend and frontend; CI runs same commands with synthetic config.
Ruling: parent outcome9 split into operations and native backup/restore milestones
because process lifecycle and recovery have independent failure/verification gates;
recovery remains required, including sessions/private images/pending paid work rules.
Ruling: reuse /admin/ai-monitoring and staff.manage (ADMIN-only), avoid new permission
or schema. Runtime bind becomes local by default; Compose explicitly overridesHOST.
Business26/test26; no pending schema change. Mailpit restart limitation persists.
Task1 next: pin aggregate DTO and bounded resource tests before implementation.
Task1 RED observed: missing operations modules (unit); route404 for all3 real
PG/Redis cases after correcting test cleanup's nonexistent session model. GREEN:
6 unit +3 real PG/Redis cases. Added real two-worker compare/delete and alternate
schema/UTC checks to cover the transport contract beyond unit doubles.
Ruling: queue oldestWaitingAt is null when prioritized jobs exist; FIFO/paused
oldest timestamp is read without payloads. Priority order does not prove oldest
insertion time. Cost: no age estimate for priority queues, counts remain accurate.
Ruling: SMTP status is only socket reachability (both local mail/recovery enable
it), provider status is configuration, and shipping mode is the implemented local
simulator. No provider acceptance or email delivery is inferred from these checks.
Task1 complete: 199/199 full native E2E with worker/storage,83unit,lint/build PASS.
Logs .tools/operations-task1-{full-e2e,unit-all,lint,build}.log. Business26 unchanged.
Task2 next: remote admin DTO/page, account isolation/mobile tests and Chrome.
Task1 commit0483432; Task2 brief read, BASE0483432. DTO/widget RED missing module
->8focused tests GREEN;425fullFlutter+2existing opt-in skips, analyze clean.
Manual GET retries only (Riverpod automatic retry disabled), owner/role-scoped data;
large VND strings formatted exactly, no numeric rounding or unknown->0 fallback.
Browser harness RED: Flutter password input needs click before fill; captured ARIA
showed empty invalid password. Corrected to the established helper's focus/fill.
First harness wait promise was unhandled; attached rejection handler so finally
always closes fixtures. Identified one interrupted synthetic fixture/queue and
removed exact verified set with private operations-orphan.cjs; business untouched.
Ruling: replace BullMQ getJobCounts with an atomic read-only Redis script because
the installed BullMQ helper RPOP-removes legacy markers. Real RED proved mutation;
GREEN6E2E preserves marker and counts paused/priority queues. No payloads are read.
Cost: monitor must track BullMQ's documented queue layout if its major version changes.
Task1 follow-up verification:200/200fullE2E,83unit,lint/build PASS after read-only
queue correction. Logs .tools/operations-queue-{full-e2e,unit,lint,build}.log.
Task2 Chrome PASS: real PG/Redis/MinIO, exact synthetic aggregates, live/stopped
heartbeat, Redis outage isolated from DB, manual refresh/recovery, ADMIN route and
customer403.375/1440 screenshots inspected, no overflow. Manager login correctly
lands on its home; harness now explicitly revisits protected deep link to test403
UI and proves no operations GET. No product/auth change needed. No external calls.
Task2 complete:425Flutter+2existing skips,analyze PASS and Chrome --operations PASS.
Task2 commit0213a15. Task3 brief read, BASE0213a15. RED: missing runtime modules,
HOST default missing, configure/build fingerprint functions missing, static factory
missing.11 tool tests now GREEN (control identity, read-only status, path/port guards,
partial rollback, stale state, native nonzero exit, local config, artifact hashes,
GET/HEAD/traversal/junction-safe static serving). Native integration not yet run.
Static RED import started the legacy preview as a side effect; test runner did not
exit despite its per-test timeout. Verified exact test-child command/parent9232/24184
and stopped only that owned child; new factory import has no server side effect.
Ruling: native builds record backend/web tree hashes and API origin; another browser
fixture build invalidates the runtime manifest. Cost: rebuild needed after fixture
or compiled-asset changes. Read-only status does not create a runtime directory.
Ruling: stale/unverified state is retained, never killed by PID; a verified stop
must observe the control listener close, not just a request timeout. Cost: operator
inspection is needed for externally terminated or damaged ownership records.
Task3 complete: real native build/start/status/stop PASS with testDB/testbucket/
UUID namespace/isolated ports, then bounded dependency failure and reused-build
acceptance PASS. API readiness/products200,private admin401,web200/noindex,worker
heartbeat present then removed; ports freed, PG/Redis/S3 still available,.env SHA
unchanged. Captured .tools/runtime/<workspace hash>/acceptance.json is credential-free.
RED->GREEN log allowlist prevents arbitrary uppercase secret strings; rotation
bounded. RED->GREEN command PATH preserves selected Node24 ahead of inherited PATH.
Final200E2E,84unit,29tooltests,lint/build PASS. Last fullFlutter425+2/analyze unchanged
fromTask2; native build compiles currentfrontend. All owned runtime children stopped.
Logs .tools/operations-task3-{native,native-final,full-e2e,unit,lint,tools}.log.
Task4 BASE25ba2b0. CI guard RED missing ci-verify ->7 tests GREEN. Prepared
Ubuntu workflow uses Node24, Flutter3.47.7, dedicated PG/Redis/MinIO and disabled
providers; fresh-checkout env only, hashes detect changes, commands stop on failure.
Ruling: acceptance.ps1 reuses existing commands serially; no redundant unit tests
for this low-impact wrapper. Run full profile itself and native runtime profile.
Cost: wrapper platform coverage is the observed Windows run, not every shell.
Ruling: hosted CI is prepared, not claimed executed; local equivalent commands
plus guards/parser checks are the evidence. No push requested. Cost: Linux-specific
runner issues can still require fixes on the first hosted run.
Task4 full acceptance PASS:200E2E,84unit,36tool,425Flutter+2 existing opt-in skips,
lint/build/analyze PASS. Log .tools/operations-task4-full.log. YAML formatted/parsed
and PowerShell AST clean. Existing serve traversal test now uses encoded slash,
valid on both Windows and Ubuntu. Docs corrected routine seed/reload/provider claims.
Checkpoint693707d. Sole independent reviewer /root/operations_review, GPT6astra high,
read-only whole milestonef649201..693707d. Two Important confirmed, no Critical.
Final: Ruling: regrade worker-start disclosure from Minor to Important documentation
because configured queued work can incur costs before start reports success;
spec/guide now disclose resumption and nontransactional rollback. Cost if wrong:
operator may still need to inspect accepted pending work before starting the app.
Final: fixed foreign reused-control-port POST — regression proved foreign /stop
was called; GREEN read-only handshake then POST on the exact same verified socket,
never reconnect. Connection-close regression also RED->GREEN. Node control keepalive
raised500ms->5s because subsecond header timeout=0 retired the verified socket.
16runtime tests PASS including partial cleanup and failed readiness/shutdown.
Final: fixed recent terminal failure window — real PG regression old-created/newly
finished UNKNOWN counted1 instead of2 RED; COALESCE(finishedAt,createdAt) GREEN7E2E.
Ruling: legacy terminal rows lacking finishedAt fall back to creation time; precise
completion cannot be reconstructed. Cost: legacy failures retain an approximate window.
Final: Ruling: native recovery excluded from this review — separate required next
milestone with actual business restore evidence, not complete; cost if omitted is
unproven recovery, so the A-Z goal remains active.
Final: Ruling: hosted CI excluded — prepared workflow/local checks only, no push;
cost is unknown runner behavior until first hosted run.
Final: Ruling: live Gemini/VNPay excluded — keys/configured response acceptance
remain required, synthetic tests do not prove acceptance; cost is provider uncertainty.
Final: Ruling: Mailpit restart acceptance excluded — automatic approval rejection
stands and is not bypassed; cost is unverified inbox survival across restart.
Final: Ruling: normal worker processes accepted jobs — retain business behavior,
disclose effects in spec/guide; cost is configured provider work on startup.
Final: Ruling: public deployment/TLS/off-host backups excluded — user chose local
only; cost is no production deployment or disaster recovery claim.
No deferred minors after regrading.
Task4 complete: final full acceptance201E2E/84unit/38tool/425Flutter+2existing skips,
lint/build/analyze PASS; fresh native build/start/status/stop PASS with same-socket
control, compiled business read-only smoke PASS. Logs .tools/operations-final-*
observed exit0. Native services/.env preserved, all owned runtime children stopped.
Ruling: record the already-observed final commands instead of rerunning identical
suites solely through task-done; developer prohibits redundant testing without
new concerns. Cost: ledger entry is manual, evidence/logs preserve command outcomes.
Ruling: preserve this whole ledger in docs/OPERATIONS_IMPLEMENTATION_LOG.md before
scratch cleanup because the parent A-Z goal continues beyond this milestone; its
final report can still expose every decision. Cost: one additional durable doc.
Ruling: finishing-a-development-branch integration remains at the parent goal's
final milestone; retain named worktree and branch now. Cost: root checkout does
not receive this work until remaining required milestones are verified.
