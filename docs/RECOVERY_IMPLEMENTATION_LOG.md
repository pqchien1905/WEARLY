# SDD ledger — plan: docs/superpowers/plans/2026-10-22-native-recovery.md

Milestone BASE8c1cb60; spec/plan098408c. Task1 BASE098408c, brief read.
Pre-flight: backup snapshot/object metadata -> complete manifest -> restore/hash
validation -> exact target comparison -> quarantine -> compiled read-only acceptance.
All stages use local source settings and fresh destination identifiers; none writes
normal.env. Native business and test both26 migrations, no schema changes planned.
Ruling: this refines the previously approved parent outcome9 and its explicit
recovery requirement; existing A-Z/local authorization covers reversible fresh
targets. No repeated approval/build-check delegation beyond one final milestone
review. Cost: technical defaults remain builder decisions, documented in spec.
Ruling: restored accounts disabled until fresh-password/ownership review, private
AI bytes excluded, pending AI/mail suppressed; preserves commerce data without
resurrecting revoked credentials or paid work. Cost: restore is quarantined and
requires deliberate operator activation, not one-click business cutover.
Task1 next: guards/object corruption RED, consistent snapshot/native archive,
private ACL and synthetic backup evidence. Never delete source or retained targets.
Task1 guards RED missing helper ->6 GREEN. Integration RED BACKUP_NOT_IMPLEMENTED
then consistent exported native backup implemented. First acceptance failed because
pg_restore SQL exceeded runNative's1MiB captured-output bound (diagnostic measured
8.5MiB, one old marker/zero new). Test now writes SQL into its private owned archive
scratch, inspects it locally and removes only that exact scratch file; no raw SQL
or row values printed. Native command output bound unchanged.
Task1 integration PASS: snapshot archive contains pre-concurrent-change marker,
source retains intentional fixture update; copied catalog object hash matches,
deleting only that synthetic object makes next backup failed (not complete).
All exact test rows/object cleaned; archives retained. First successful archive
for subsequent investigation1792631725995-8542aec7-21ea-499f-93ae-dc261c6fdb6d.
Ruling: archive stores snapshot transaction time, not completion time, and streams
table/hash reads. No old private photo bytes copied; DB metadata still archived
privately and requires Task2 quarantine before any restored application use.
Task 1: complete (commits 098408c..f76bed5, tests: .tools/node-v24.22.0-win-x64/node.exe tools/verify-native-recovery.cjs → Retained archive: D:\Fashion Shop\.tools\recovery\0e2e53abed9b08caecc6\1792631797466-daf95c1a-3887-4498-9ec2-11cee5f86778)
Task2 BASEf76bed5, brief read. Guard RED missing assertFreshTargets/quarantine ->
9 tests GREEN. Full integration RED RESTORE_NOT_IMPLEMENTED; fresh target restore
and quarantine implemented in separate recovery-restore.cjs to keep orchestration
readable. Ordinary app owner runs pg_restore; admin only creates fresh DB/revokes
PUBLIC connect. No cleanup of failed targets, source data or old backups.
Fixture failure: browserScope='store' violates existing customer/admin constraint;
corrected fixture to customer. Exact restore surfaced three equivalent PostgreSQL
varchar-array text coercion rewrites. Ruling: normalize only literal varchar[]->
text[] coercion placement, preserving values/types/operators, never strip arbitrary
casts. Cost: other future equivalent DDL forms still fail closed for investigation.
Literal-preservation regression RED showed casts inside quoted values changed;
replacement now matches complete quoted literal plus its external cast only.
Quarantine exact expected-row hashes RED because now() has microseconds but Prisma
columns are TIMESTAMP(3); explicit timestamp(3) makes expected/actual identical.
Synthetic full backup/restore GREEN: exact pre-quarantine data/schema, account
disable/session revocation/reset consumption/photo tombstone/result expiry,
AI UNKNOWN with cost3000 preserved, pending job/mail/outbox suppression, private
object absent from restored bucket, catalog bytes equal, full source snapshot
unchanged by restore. Existing-target guard rejects the retained destination.
Compiled restored API readiness/catalog/content and managed bytes PASS; correctly
signed bearer referring to old session401, private admin401; no worker started.
Logs .tools/native-recovery-task2-{integration,api}.log. Last successful source
archive1792632446980-90dfed32-2c23-495e-987a-c757b70bca2a. Business DB untouched.
Task2 still needs final guard/CLI verification and commit; Task3 real business
backup/restore, operator docs and the sole independent review remain.
Final Task2 guards50/50 all Node tools PASS, including corrupt archive before target
creation and exact literal-preserving constraint normalization. Mixed-case inherited
libpq routing/secret keys now cleared through shared environment helper RED->GREEN.
Windows ACL checked protected with exactly current-user+SYSTEM allow entries;
PowerShell wrapper AST clean, backup/restore arguments explicit. No product code
changed, so unrelated backend/Flutter suites not repeated. Final task-done runs
full synthetic restore/API acceptance again after these helper changes.
Task 2: complete (commits f76bed5..ffe77d0, tests: .tools/node-v24.22.0-win-x64/node.exe tools/verify-native-recovery.cjs → Retained archive: D:\Fashion Shop\.tools\recovery\0e2e53abed9b08caecc6\1792632675200-b6e243fa-3d23-4bdb-b007-7886daba35a8)
Task3 BASEffe77d0, brief read. Actual business read-only backup/restore PASS:
42public tables,7bundled assets,0managed objects; source/env SHA unchanged,
exact target snapshot and quarantine verified, compiled target API200/private401.
Archive1792632721270-93ce3083-478e-4902-8f3a-ac6b63cd568a; retained target
wearly_recovery_1792632721963_d5cae7e8; evidence private business-acceptance.json.
No active store switch, account reactivation, worker or paid calls. Native services
stay alive. Guide added; historical Docker drill explicitly distinguished.
Ruling: native source has0managed images, so actual business drill verifies its
seven bundled images and42tables; managed S3 bytes verified with real synthetic
source/restore/API. Cost: no claim that business already contained custom uploads.
Ruling: failed targets retained before quarantine may still contain old active
accounts/work; no inspection.env exists until quarantine succeeds. Guide forbids
starting an app on those targets. Cost: operator must keep failed artifacts private.
Task3 sole independent review pending; no product code changed, so last product
suites201E2E/84unit/425Flutter+2skips remain unchanged from operations milestone.
Current tooling50tests PASS and real compiled source/target acceptance supplied.
Sole reviewer native_recovery_review (gpt-6-astra high, fresh context) reviewed
8c1cb60..dbc17f5. Important: malformed schema metadata reached destination creation;
Important: API acceptance lacked verified archive/report/assets and schema status;
Minor evidence-overclaim regraded Important because operators could believe an
unperformed check passed. One fix pass, no rereview or further agent delegation.
Schema validator regression RED missing implementation -> GREEN; all eight schema
arrays/entry fields validated before native/config/network/target actions, plus
malformed archive regression confirms no output creation. Context regression RED
missing helper -> GREEN: matching private report/targets, archive hashes, current
bundled hashes required; missing/changed assets fail before application startup.
Ruling: data restore completion remains independent of application compatibility;
assets/schema/API explicitly verified/mismatched/unverified. Compiled schema probe
checks current generated fields/enums; not a blanket cross-version UI guarantee.
Cost: operator must supply matching built code/assets for application verification.
Ruling: performed/skipped reports replace unconditional success prose. Business has
no managed image/old-session fixture; these are explicitly skipped there and both
performed by full synthetic acceptance. No overclaim from earlier checkpoint prose.
Final 53Node guard tests PASS; synthetic full restore/API PASS with zero skipped
checks. Business full backup/restore PASS with42tables/7bundled/0managed, source/env
unchanged, assets/schema/API verified. New archive1792633566825-4585827c-90d0-4f02-8b86-98b19eca90b4,
targetwearly_recovery_1792633567495_fa0e0284. Logs .tools/native-recovery-review-
{tools,integration,business}.log. Owned API children closed; native services alive.
Declined review expansion: off-host/production backups, automatic cutover/account
activation, same-account malicious archive authentication excluded by local trusted
contract. Unrelated product suites not rerun; no product code changed. No deferred
minors remain. Parent integration deferred until identity/policies/SEO and provider
acceptance complete; existing authorization continues, no repeated approval gate.
Task 3: complete (checkpoint dbc17f5 plus final review fixes, 53 tool tests and
fresh synthetic/business compiled application acceptance all PASS).
