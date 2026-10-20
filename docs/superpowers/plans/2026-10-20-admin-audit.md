# Persistent administration activity

Grounding: the existing demo dashboard renders `AdminState.audit` under
"Thay đổi gần đây"; the remote dashboard currently omits this capability.

## Scope and design

- Add an `AdminAuditEvent` table, without changing existing rows or columns.
- Record actor UUID, action enum, target UUID and timestamp for successful
  product/SKU/taxonomy/inventory/order administration writes.
- Insert the event within the same transaction as the business change.
  Conflicts/validation failures must not create success events; audit insertion
  failure must roll back the business change.
- Actor/target IDs are historical identifiers, intentionally not cascading
  foreign keys. No request bodies, credentials, customer addresses, or image
  URLs are copied into this table. No event update/delete API.
- Add ADMIN-only `GET /admin/audit` with bounded pagination, newest first,
  deterministic ID tie-breaker and consistent count/items snapshot.
- Show the history on the existing remote dashboard with paging, refresh,
  loading/error/empty states; preserve existing design tokens and auth lifecycle.
- This is application activity history, not an independently tamper-proof
  compliance store. No retention/deletion policy is invented.

## Execution and verification

1. Reproduce missing protected endpoint with E2E regression.
2. Add migration, transaction recording and read contract.
3. Verify actor provenance, all mutation categories, conflict cardinality,
   non-disclosure, rollback and pagination against dedicated PostgreSQL test DB.
4. Add dashboard UI and widget checks for data, retry/paging and narrow viewport.
5. Run backend lint/build/unit/E2E, Flutter checks and real admin browser journey.
6. Verify fresh migrations/seed and update audit/progress/handoff evidence.

Only dedicated test databases receive migrations during this work.
Production rollout remains outside authorization.
