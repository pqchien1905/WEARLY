# Persistent style preferences implementation plan

> Execute inline with executing-plans, TDD and one fresh final branch review. User authorizes continued completion of remaining features.

**Goal:** Activate the existing customer style profile in API mode with durable, private and conflict-safe preferences.
**Architecture:** Extend Users module, existing AccountDetailsRepository/controller and StylePage; PostgreSQL one-to-one StylePreference row. Keep the demo path and existing visual design. No external provider/dependencies.
**Tech stack:** NestJS/Prisma/PostgreSQL, Flutter/Riverpod, Chrome integration harness.
**Spec:** Existing StylePage/domain options and the style preferences backlog in docs/migration-plan.md; user continuation. Implementation choices below are assistant defaults within that scope.

## Global constraints and design

- GET `/users/me/style` returns `{size,style,color,budget,version}` scoped to authenticated user. No row means defaults M/empty style/empty color/budget string1500000/version0, without DB writes.
- PUT same path replaces all four selections with `expectedVersion` integer>=0. Defaults/options exactly match current UI: sizes XS,S,M,L,XL,XXL; styles empty,Tối giản,Thanh lịch,Thư giãn; colors empty,Trắng,Đen,Mận,Xanh,Nâu,Hồng đất,Tím,Đỏ; budgets strings800000/1500000/2500000. Unknown fields/null/invalid options rejected400; no supplied userId. Stale version409.
- New StylePreference table userId UUID primary/FK cascade, size/style/color, budget Decimal(14,0), versionInt starting1, timestamps. Transaction + lockUser handles concurrent initial creates and updates; monotonic version, no destructive migration. No automatic AI/body inference.
- Extend StylePreferences with version default0; remote AccountDetails read aggregates addresses and style (same DB), validates style response and maps monetary strings exactly. Existing account cache/session guards retained. saveStyle sends snapshot expectedVersion and returns persisted style plus address data; no replay after uncertain results.
- Controller saveStyle returns saved preferences after identity check. StylePage uses existing form, stores version from the loaded snapshot and successful response. Remote form has online persistence copy, no demo success message or AI navigation. Size remains preference, not measurement.
- After 409/uncertain write error disable save and provide explicit reload before another write. Preserve validation400 retry; lock controls while saving. Explicit reload discards draft and reads server state. Late HTTP completion after timeout invalidates account data only for same mounted repository/session, without replay or restoring old identity.
- Remote style route removed from unavailable gate, customer login required with return path. Staff-only identity never opens customer profile. Same UI 375/1440, existing Manrope/BeVietnamPro and plum tokens; no new decorative layout or images needed.
- Keep demo style/AI flow intact. Shared AccountDetails read adds one bounded style request; regression-check address/checkout behavior. No mail, promotions, AI or payment provider implemented in this increment.

## Review focus

- First-save races, stale forms and consecutive saves; expectedVersion must remain tied to the visible snapshot.
- Logout/relogin while loading/saving, same identity session replacement and late timed-out completion.
- Invalid or missing fields, money string mapping, default profile without creating data, caller-supplied identity.
- Address/checkout regression from aggregated read and post-write read failure; no success on unknown result.
- Honest UI about persistence and unavailable AI, mobile dropdowns and reload recovery without duplicate mutations.

### Task 1: API and persistence
Files: schema.prisma/migration, users/style.service.ts, dto/style.dto.ts, users controller/module, test/style.e2e-spec.ts.
Interfaces: GET/PUT users/me/style contract above, no changes to auth/user or addresses responses.
- [ ] Add tests for private defaults, validation, durable isolated roundtrip, concurrent create/update/version conflicts. Run tools/test-backend.ps1; expected RED404.
- [ ] Implement table/service/controller/DTO. Run migration/generate, E2E/unit/lint/build; expected PASS. Commit.

### Task 2: Existing Flutter profile integration
Files: domain/account_details.dart, data/remote_account_details.dart, app/account_details.dart, account/style_page.dart/account_navigation.dart, app/remote_route_gate.dart; remote style and UI tests.
Interfaces: StylePreferences.version, saveStyle -> saved StylePreferences, late completion invalidates current session account cache.
- [ ] Write repo/UI regressions first: remote save payload/version, validation, loaded values, second save, conflict/timeout reload, late/logout, guest/staff gate, no demo/AI claims; observe RED.
- [ ] Implement using existing form/account repository, update affected HTTP fixtures for style read. Full Flutter/analyze expected PASS; preserve demo/account/address behavior. Commit.

### Task 3: Live flow, docs and integration
Files: tools/test-frontend-api.cjs + verify-style-browser.cjs; docs/api.md/database.md/migration-plan.md/progress.md and style-preferences.md.
- [ ] Live Chrome/PostgreSQL: customer save, reload/login persistence, change/save again, second account defaults, viewport375/1440 screenshots; exact fixture cleanup only. Expected PASS.
- [ ] Deploy additive migration native, restore localhost3000 web build, restart only owned API, preserve user Flutter. Update documentation and evidence.
- [ ] Fresh final review, one Important fix pass RED/GREEN/full affected suite if needed; fast-forward/push under prior authorization. Retain ignored evidence.
