# Local handoff acceptance audit

> Execute inline with executing-plans. The active goal is the user's full local handoff objective, interpreted against the original Master Prompt and later explicit requests, not against whichever tests happen to pass.

**Goal:** Close unproven handoff gates with stronger evidence and identify any required unfinished work before deciding completion.
**Architecture:** Read-only source/history audit and browser checks; bounded local tooling under ignored .tools. Existing frontend/backend and user data preserved. Any actual product bug must be reproduced before a focused fix.
**Tech stack:** Git, Gitleaks official checksum-verified binary, Node/Playwright/Chrome, existing NestJS/Flutter checks.
**Spec:** User active goal and attachment1064c7c6-b822-43ba-a47a-80403e150132/Pasted text.txt sections1–14; later native PostgreSQL/npm, F12, independent sessions/direct admin, review history requests.

## Constraints

- No data deletion, production changes, paid provider activation or history rewrite.
- Never print discovered secret values. Scan reports redacted and ignored; findings require classification, not blind allowlisting.
- Preserve Flutter and its state management; optional future AI/payment/promotions are not falsely called implemented. Whether they block handoff follows the actual specification, not convenience.
- Required artifacts, APIs, security controls, migrations, tests, diagrams and Windows commands require explicit evidence. Preserve current scope beyond the original foundation (admin/customer separation, wishlist/reviews/history/style/retry fixes).
- Reuse recent passing checks on unchanged source; rerun only when evidence is insufficient or a fix changes relevant behavior.

## Review focus

- False-positive secret findings vs genuine credentials, including historical commits.
- Swagger JSON works but UI fails due to browser headers/resources.
- Source diagrams diverge from schema/modules or cannot parse.
- Documentation assumes one configured machine and omits first-install steps.
- Completion wording hides missing required functionality or expands scope into optional production work.

### Task 1: Strengthen acceptance evidence

- [ ] Install checksum-verified official Gitleaks under ignored .tools and scan all reachable Git history with redaction; classify findings without exposing values.
- [ ] Load Swagger in headless Chrome, inspect endpoints/auth UI/resources/errors; validate four Mermaid sources with a local parser/render if available.
- [ ] Inspect required source/config/test artifacts and compile a requirement-by-requirement acceptance matrix; fix only proven gaps with regression evidence where behavior changes.

### Task 2: Review and hand off

- [ ] Update actual setup, handoff report and PROGRESS with results, decisions, commands, limitations and remaining required work.
- [ ] One read-only final review, one Important/Critical fix pass, affected checks; integrate under existing authorization.
- [ ] Complete the goal only if all explicit local handoff requirements and later user changes are proved; otherwise leave active with concrete next work.
