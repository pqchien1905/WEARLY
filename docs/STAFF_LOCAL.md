# Local staff accounts and audit history

Staff use `/admin/login`. Register an account through the customer registration
form first; an existing administrator can find that exact email under **Nhân sự &
quyền** and assign a role. No shared password or default staff account is created.

| Role | Available operations |
| --- | --- |
| ADMIN / Quản trị viên | All operations, including staff roles and account activation |
| MANAGER / Quản lý | Store operations, reports, catalog, inventory, orders, money, returns, promotions, content, support and mail status |
| WAREHOUSE / Kho | Inventory adjustment, order reading/fulfillment, local shipment events and receiving approved returns |
| SUPPORT / Hỗ trợ | Reading orders and handling support requests |
| CUSTOMER / Khách hàng | Customer functions; no administrative access |

Only ADMIN can grant/change roles. Staff home opens inventory for warehouse and
support requests for support agents. Navigation and order controls follow the role;
API guards enforce the same boundaries even when requests bypass the interface.
Order readers can see order totals and payment status to support fulfillment and
customer questions. Warehouse/support cannot collect COD or issue refunds.

## Changing a staff account

1. Sign in as ADMIN, open **Nhân sự & quyền**, and search the registered email.
2. Choose **Đổi quyền**, select the role and whether the account remains active.
3. Save. A successful actual change ends every current session of that account,
   including customer and administrative sessions. The person signs in again.

The displayed account version protects against overwriting another administrator's
change. On conflict or an uncertain response, reload the account before another
change. Repeating an already-applied identical state does not add another audit row.
Changing your own role ends your local admin session after success. The backend
refuses changes that would leave no active ADMIN, including simultaneous edits.
Failed audit persistence rolls back the role, version and session revocation.

The customer list contains CUSTOMER accounts only. Staff lookup/listing returns
identity, role, activation and version fields; never credentials or reset tokens.

## Audit details

The overview history shows actor, action, target and available old/new scalar values.
Examples include inventory quantity, SKU price, order/return/refund state, promotion
limits, content versions and staff role/activation. Amounts retain integer VND.
These snapshots are committed in the transaction that performs the change.

Audit fields are allowlisted per action. Messages, addresses, names, descriptions,
free-text reasons, passwords, tokens, mail contents and provider secrets are excluded.
Taxonomy/image events retain the actor/action/target without copying text or paths.
Older events keep empty details; history is not reconstructed or backfilled.

## Verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-backend.ps1 -WithWorker -WithStorage
node tools/test-frontend-api.cjs --staff
```

The staff backend suite creates its own random schema inside the dedicated `_test`
database to verify last-admin races without changing other accounts. It migrates
and removes only that owned schema. The browser harness creates uniquely named
synthetic accounts/orders in `_test`, verifies role grants, warehouse stock and
delivery, denied money/staff access, support reply persistence and demotion.
It never changes staff roles in the normal business database.

Persistent browser sessions are implemented in a separate milestone; until then,
refreshing the browser requires signing in again. Do not put JWTs in browser storage.
