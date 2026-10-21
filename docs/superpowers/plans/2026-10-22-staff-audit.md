# Staff permissions and audit details implementation plan

> Execute inline with executing-plans and test-driven-development; one fresh final
> review, then one tested fix pass. Existing A-Z authorization covers this work.

**Goal:** Give staff only the operations needed for their role and retain useful,
non-sensitive before/after evidence of successful administrative changes.
**Architecture:** One backend capability map enforced by the existing session guard;
versioned staff changes and session revocation in one transaction; explicit safe
audit snapshots; Flutter navigation/actions match the same role matrix.
**Tech stack:** Existing NestJS, Prisma/PostgreSQL and Flutter/Riverpod.
**Spec:** docs/superpowers/specs/2026-10-21-local-completion-design.md, outcome8.
**BASE:** bfbef9c. Persistent browser sessions remain the next separate milestone.

## Global constraints and decisions

- Keep existing CUSTOMER/ADMIN accounts unchanged. Add MANAGER, WAREHOUSE, SUPPORT.
  Registration never accepts a role. ADMIN alone manages staff; manager is not an
  administrator. No default credentials or automatic business-data promotions.
- Capabilities: reports.read, audit.read, catalog.read, catalog.write,
  inventory.read, inventory.write, orders.read, orders.fulfill, orders.cancel,
  payments.manage, returns.decide, returns.receive, customers.read,
  promotions.manage, content.manage, support.manage, mail.read, staff.manage.
- ADMIN has all. MANAGER has all except staff.manage. WAREHOUSE has inventory.read,
  inventory.write, orders.read, orders.fulfill, returns.receive. SUPPORT has
  orders.read and support.manage. CUSTOMER has none. Order readers can see order
  amounts/payment states to answer customers; money mutation remains restricted.
- Existing @Admin() defaults to ADMIN-only; @Admin(capability) requires the named
  capability. Unknown/new protected endpoints remain denied to other roles.
  Guard checks the current database role/active session, never trusts JWT role.
- Staff list/search returns only id/name/email/role/active/staffVersion/createdAt.
  Exact normalized email search can find an existing customer for promotion.
  PATCH requires expectedVersion, role, active. No password/profile editing here.
- Serialize staff mutations with one transaction advisory lock; recheck current
  actor ADMIN+active under row locks, protect the last active ADMIN, and revoke all
  target refresh sessions when role/active changes. Same desired current state is
  a no-op; mismatched stale state is409. Audit failure rolls back every side effect.
- Audit details are an explicit allowlist of scalar state fields, never raw DTOs,
  addresses, names, email, notes, bodies, passwords, reset tokens or provider secrets.
  Older events retain empty details; do not fabricate historical before states.
- Existing useful sales/settlement/inventory summary remains reports.read. Native
  local scope, additive migration, verified backup/original-data fingerprints.
- UI retains design tokens and demo behavior. Staff home routes: ADMIN/MANAGER
  overview, WAREHOUSE inventory, SUPPORT support. Deep links and controls follow
  permissions, and backend always remains the authority. Staff page ADMIN-only.

## Review focus

1. Stale access tokens after demotion/deactivation must fail immediately; role
   change and revocation roll back together on audit failure (Task1 API).
2. Concurrent removal of the last administrators cannot leave zero active ADMINs;
   version conflicts must not overwrite newer choices (Task1 real PostgreSQL).
3. Every protected endpoint must deny a role without its capability, including
   image upload, money operations, returns and content (Task1 route matrix).
4. Audit snapshots must not leak nested/raw sensitive fields or claim an invented
   historical value; successful changes have accurate quantities/statuses (Task2).
5. Staff deep links cannot mount forbidden repositories, and read-only order users
   cannot trigger money/fulfillment actions from hidden controls (Task3 widget/Chrome).

## Task 1: capabilities and staff account administration

Files: backend/src/common/permissions.ts; decorators/auth.ts; guards/auth.guard.ts;
modules/auth/auth.service.ts; protected controllers; modules/admin/staff.dto.ts,
staff.service.ts, staff.controller.ts, admin.module.ts; Prisma schema/migration;
test/staff.e2e-spec.ts.

Interfaces: can(role, capability):boolean and isStaff(role):boolean; Admin(capability?)
metadata; GET /admin/staff?email=&page=&limit= -> paginated safe users;
PATCH /admin/staff/:id {expectedVersion,role,active} -> safe user.
User.staffVersion starts0; AdminAuditEvent.details JSON defaults{}; new STAFF_UPDATED.

- [x] Write API tests for admin-only lookup/change, invalid role/body, customer
  registration escalation denial, role login and route matrix, version/no-op,
  concurrent last-admin removal, revocation, and injected audit failure rollback.
- [x] Run focused Jest with TEST_DATABASE_URL ending_test. Expected RED404 for new
  staff endpoints / staff login denied; no edits to business data.
- [x] Add additive migration, regenerate client, deploy testDB sequentially. Implement
  capability guard and annotated routes; staff transaction uses advisory lock before
  user locks in sorted-ID order, rechecks actor, target, version and last-admin count.
- [x] Run focused staff/auth tests. Expected PASS; lint/build. Commit checkpoint.

## Task 2: safe before/after audit snapshots

Files: modules/admin/audit.ts and audit-snapshot.ts; admin/taxonomy/content/catalog-media/
promotions/shipments/returns/refunds/support mutation services; test/audit.spec.ts,
test/staff.e2e-spec.ts and existing commerce tests.

Interfaces: recordAdminActivity(tx,actorId,action,targetId,{before?,after?}?) sanitizes
through auditSnapshot(action,unknown). Details {before:{...},after:{...}}, bounded
scalar fields only. Capture the original row inside the same locked transaction.
Allowed fields by action: product active/tryOnSupported/categoryId/brandId; SKU active/price/
productId; inventory quantity/version; order status/version; COD status/amount;
content version/publishedVersion; promotion kind/amount/minSubtotal/maxDiscount/
usageLimit/perUserLimit/startsAt/expiresAt/active/version; shipment status/version;
return status/version/amount; refund status/provider/amount/primary; support
status/version; staff role/active/staffVersion. Taxonomy names and image content
are intentionally omitted; their action/target still identify the change.

- [ ] Write unit sanitizer rejection tests and real API before/after assertions for
  product, inventory, order, support and staff; rollback assertions remain covered.
- [ ] Run tests. Expected RED missing details or sanitizer. Implement explicit
  snapshots at mutation sites, excluding notes/messages/addresses and external IDs.
- [ ] Run full backend E2E/unit, lint/build sequentially. Expected all PASS; commit.

## Task 3: permission-aware admin UI and local acceptance

Files: frontend/lib/domain/staff_permissions.dart; app route/providers; admin shell,
login, remote pages/return actions/audit panel; new remote/staff_page.dart;
data/remote_admin.dart; test/staff_test.dart; tools/test-frontend-api.cjs --staff;
docs/STAFF_LOCAL.md and LOCAL_COMPLETION_PROGRESS.md.

Interfaces: canStaff(role,capability), staffHome(role), canVisitAdmin(role,path);
admin staff search/update repository and paginated records. UI changing own role
clears local admin session after confirmed success; stale result offers reload.
Audit view renders translated field labels with old/new scalar values, not raw JSON.

- [ ] Write widget/repository tests for role navigation/deep links, hidden order and
  return controls, versioned staff edit/conflict and before/after audit details.
- [ ] Run focused Flutter tests. Expected RED missing permissions/page/controls.
- [ ] Implement existing-style responsive UI and role-aware repository gates; preserve
  account-change invalidation and separate customer/admin sessions.
- [ ] Full Flutter/analyze and Chrome --staff: register synthetic accounts in_test,
  admin grants roles, warehouse inventory/order read + denied money, support ticket
  handling + denied staff, demotion invalidates session, reload/persistence,375/1440.
  Expected PASS; never change business staff accounts to test.
- [ ] One independent review; important fixes RED->GREEN with green required suites.
  Verified business backup, migration, original-table fingerprints and compiled
  read-only smoke. Update guide/ledger, commit and remove only this plan's scratch.

Self-review: covers outcome8 roles/audit and preserves existing reports. Persistent
sessions are separately tracked next; AI/operations/SEO remain in the full ledger.
