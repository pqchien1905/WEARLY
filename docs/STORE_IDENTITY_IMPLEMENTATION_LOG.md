# SDD ledger — plan: docs/superpowers/plans/2026-10-22-store-identity.md

Milestone BASE94e0235, spec/plan db84626. Existing isolated worktree verified.
Ruling: parent A-Z/local authorization covers this bounded refinement; optional
identity question unanswered, announced WEARLY local-demo/blank-contact default.
No new approval or builder-check delegation; one final reviewer after implementation.
Cost: merchant identity remains editable, no invented real details or policy promises.
Preflight: backend default details == Flutter fallback; old omission preserves JSON;
published-only consumers; HTML origin independent of Host; local noindex explicit.
Task1 BASEdb84626: add E2E evidence then additive test migration and implementation.
Task1 RED missing details response; implemented nullable JSON pair, strict nested
validation, defaults, atomic publication and legacy omission preservation.
Five real-PG content tests GREEN, lint/build PASS. Test DB now27; business stays26
until backed-up additive migration acceptance. No provider calls. Audit keeps
existing scalar allowlist (no full contact/policy text in audit snapshots).
Ruling: Flutter details model belongs to Task2 consumer implementation, not backend
commit; interface is fully defined in spec/API. Cost none to external contract.
Task 1: complete (real PG5tests, lint/build PASS).
Task2 BASEcf2ea4f. User now explicitly chose WEARLY/local-demo; default confirmed.
Widget RED missing identity payload/render -> implemented editor, published model,
header/footer/contact and policy/terms surfaces. FAQ updated for actual Gemini,
VNPay sandbox, simulator and COD reconciliation. New contact GET exposed overly
broad mocks in reset/support tests: they counted all requests as writes or decoded
empty GET body. Add explicit public-content response, preserve original mutation
assertions; no product workaround. UI uses existing design tokens/forms and clear
labels, blank contacts hidden, explicit published-content errors.
Flutter427 PASS+2 existing opt-in skips. Chrome full-admin baseline failed before
identity: test database has172 brands, new Studio fixture sorts past first page;
saved successfully but harness assumed page1. Ruling: prefix this unique fixture
display name AAA for deterministic first-page placement, keep UUID slug and all
persisted assertions; no product behavior change or deletion of preexisting data.
Second browser reached published terms successfully; duplicated BrandMark parent
label+child text made accessible name repeat. Regression RED Local Shop twice ->
exclude child semantics, keep one meaningful parent label. Browser checks button
by accessible name. No repeated raw text locator workaround.
Third Chrome attempt passed all new identity/publication checks and screenshots;
later old harness expected customer list to contain staff and obsolete heading.
Staff milestone intentionally separated those views. Update baseline assertions
to current customer-only contract (customer present, admin absent); preserve all
independent shopper/admin login/logout gates, rerun full browser.
Early independent Task3 data prerequisite: native backup1792634251621-62861a61-
2e56-4280-8a59-897d48270a4e then business26->27 PASS. All41 business-table hashes
unchanged after projecting away new nullable fields; existing migration rows and
schema unchanged; env hash preserved. Evidence private archive/identity-migration.json.
Task2 final Chrome full-admin PASS1440/375 with persisted publication/identity,
terms screenshots, existing CRUD/stock/COD/activity and shopper/admin scope gates.
Source business unchanged by browser.8 focused widgets PASS after accessible-name
fix, full427+2skips before that final narrow fix, analyze clean. Full suite final
milestone acceptance will include new semantics regression (expected428).
Task 2: complete (Flutter evidence and Chrome full-admin PASS).
Task3 starts with source migration prerequisite already complete. Scratch HTML
implementation prepared while Chrome ran; install only after new HTTP tests show
missing route RED. Current backend remains unchanged during browser execution.
Task3 BASE79d6a96. HTTP tests RED404, origin config RED missing default. Implemented
escaped HTML/published identity, loopback canonical+Flutter links, active-only bounded
sitemap and noindex/no-store including404. Initial fixture publication failed DB
check because publishedVersion omitted; set fixture version1, constraint unchanged.
Unit85 PASS including origin validation. HTML tests rerun after fixture correction.
Task3 HTTP/content7 PASS after fixture fix. Full acceptance PASS204E2E,86unit,
53tool guards,428Flutter+2existing opt-in skips,lint/build/analyze. Compiled native
business read-only smoke PASS readiness/products/content and new HTML/sitemap/
robots200 noindex/no-store, private401; no writes. Native runtime verification
running next; one final reviewer remains. No live Gemini/VNPay or hostedCI claim.
Native runtime PASS: compiled API/worker/web start/status/stop, heartbeat removal,
ports released, native services/env preserved (.tools/identity-runtime.log).
Sole fresh reviewer store_identity_review (gpt-6-astra high),94e0235..d239bde:
no Critical/Important; one Minor case-insensitive Express aliases miss noindex/
no-store middleware. Grade remains Minor for local exposure. Ruling: fix under
user's explicit A-Z remediation and this spec's all-preview-header requirement;
one bounded regression, not a new feature or approval gate. Cost: lowercase match
also protects uppercase aliases. RED observed missing header; one fix pass only.
Declined: production indexing/legal assurances/live providers/hostedCI outside this
local milestone; recovery/runtime not replayed by reviewer (executor evidence
exists); static tab branding/transient default name immaterial to WEARLY selection.
Accept these exclusions. No rereview, no additional agent. Final targeted test,
lint/build and business smoke follow; full suite already green before narrow fix.
Final review fix GREEN2realHTTP tests,lint/build PASS; compiled business smoke PASS
after build. No deferred findings. Task 3: complete (d239bde checkpoint plus final
mixed-case header fix/evidence). Full implementation milestone complete; A-Z goal
still active for root integration and configured provider acceptance.
