# Wearly Backend Implementation Plan

> **For agentic workers:** Use `executing-plans` inline, as selected by dev-flow. The user authorized audit, design and implementation in the attached master prompt.

**Goal:** Preserve the existing Flutter application and establish a tested NestJS/PostgreSQL commerce backend with a separate AI worker.

**Architecture:** Modular monolith, PostgreSQL as source of truth, Redis/BullMQ for background work. Catalog is the first opt-in Flutter remote repository; other demo repositories remain explicit.

**Tech Stack:** Existing Flutter/Riverpod/go_router, Node 24 LTS, NestJS 11, TypeScript 5.9, Prisma 7, PostgreSQL, Redis, BullMQ, S3/MinIO.

**Spec:** User's 2026-10-18 master prompt; existing `fashion_ai_commerce_agent_spec (1).md`, `docs/frontend-architecture.md` and `docs/api-contracts-frontend.md`. New prompt takes precedence.

## Global Constraints

- Work in `D:/Fashion Shop`; preserve all existing code, documents, assets, state management and UI.
- Main apps become `frontend/` and `backend/`; no empty placeholder modules claimed complete.
- `/api/v1`; UUID identities; Decimal money; SKU inventory; snapshots; transaction-safe checkout and cancellation; idempotency.
- No plaintext passwords/tokens in DB/logs, no real AI or payment success without a configured provider.
- PostgreSQL migration history, repeatable seed, real DB integration tests where environment permits.
- No Git metadata exists: cannot preserve commits, create worktree or commit; retain files in place and record this limitation.

## Review Focus

1. Last SKU bought simultaneously: one success, one stock conflict, never negative stock.
2. Retry checkout/cancel and simultaneous refresh: no duplicate order, no double restock, no token reuse.
3. User-supplied price/role/resource IDs: validation and ownership must prevent escalation.
4. Same-variant catalog filters and stable pagination: matching size/color/price/stock belong to one SKU.
5. Disabled/misconfigured AI and queue outages: never manufacture completed results; preserve inspectable failures.

## Task 1: Audit, move, runtime and schema

Files: `docs/architecture.md`, `docs/diagrams/*`, `frontend/` (move all of `apps/storefront`), `tools/*`, `backend/package.json`, `backend/prisma/*`, `docker-compose.yml`, env examples.

Produces PrismaClient/PrismaService, models User/RefreshToken/Address/Category/Brand/Product/ProductVariant/ProductImage/Inventory/InventoryMovement/Cart/CartItem/Order/OrderItem/Payment/Coupon/WishlistItem/Review/ImageAsset/AIJob/TryOnResult.

- [ ] Baseline Flutter test; inventory and path audit.
- [ ] Write decisions and repository mappings before changes; hash source files before/after move.
- [ ] Configure dependencies, Prisma schema/migration and idempotent seed; validate/generate.
- [ ] Docker config/health checks and host/container documentation.

## Task 2: API foundation, auth, users and catalog

Files: `backend/src/config/*`, `common/*`, `database/*`, `modules/{auth,users,products,health}/*`, `backend/test/*`.

Interfaces: bearer JWT with session ID; `PrismaService` dependency; errors `{error:{code,message,requestId,retryable}}`; catalog `{items,total,page,limit}` with Decimal serialized as strings.

- [ ] Write integration tests for register/login/refresh/logout, whitelist rejection, ownership, catalog filtering, health and Swagger; observe failure before implementation.
- [ ] Implement environment validation, guards/RBAC, Argon2id, rotated hashed refresh tokens and revoked sessions.
- [ ] Implement owned profile/address operations and public catalog/facets.
- [ ] Run build, lint, unit and DB tests.

## Task 3: Cart, inventory, orders and admin

Files: `modules/{cart,orders,admin}/*`, `integrations/payments/*`, `test/commerce.e2e-spec.ts`.

Interfaces: `POST /cart/items {sku,quantity}`, mutations by item UUID; `POST /orders {addressId,shippingMethod,expectedSubtotal}` plus `Idempotency-Key`; UUID order ownership; COD pending payment.

- [ ] Tests: backend repricing, last-item concurrency, idempotency, cancellation restock once, authorization and illegal admin transition.
- [ ] Implement conditional stock decrement, snapshots, inventory movements, serializable retry, per-cart advisory transaction lock.
- [ ] Implement guarded catalog/inventory/orders/users administration; no client role assignment.
- [ ] Run concurrency/integration tests against PostgreSQL; report inability separately if unavailable.

## Task 4: AI queue and storage foundation

Files: `modules/ai/*`, `queues/*`, `worker/*`, `integrations/ai-providers/*`, `integrations/storage/*`.

Interfaces: create/poll owned AIJob using verified owned ImageAsset and SKU; default disabled provider, no simulated output. Outbox dispatcher ensures durable queue publication; worker retries bounded with timeout.

- [ ] Tests: disabled provider, ownership, missing consent, sanitized failure, completed job idempotency.
- [ ] Add separate worker entrypoint, adapter interfaces, private storage signed access and status handling.
- [ ] Clearly record unimplemented provider/upload lifecycle rather than claiming a finished Try-On feature.

## Task 5: Flutter remote catalog

Files: `frontend/lib/core/network/*`, `frontend/lib/data/remote_catalog.dart`, `frontend/lib/app/{config,providers}.dart`, `frontend/test/remote_catalog_test.dart`.

Interfaces: existing ProductRepository, HTTP client, `API_BASE_URL` and `USE_REMOTE_CATALOG` dart defines. Decimal JSON -> integer VND with exact validation. All mock repositories retained.

- [ ] Tests first: mapping, facets, query translation, 401/400/timeout/network failure.
- [ ] Add opt-in remote repository; safe ephemeral token store; no credentials in browser persistence.
- [ ] Preserve screens and show errors through existing Riverpod states; block unimplemented remote writes explicitly.
- [ ] Flutter pub get/analyze/test/build; live catalog API smoke.

## Task 6: Documentation, review and delivery

Files: `README.md`, `backend/README.md`, `docs/{architecture,database,api,setup,migration-plan,progress}.md`, `docs/diagrams/*.mmd`.

- [ ] Document actual files/endpoints, decisions and remaining mock boundaries; Mermaid system/modules/ERD/order sequence.
- [ ] Run available required verification commands, record exact results/blockers.
- [ ] One fresh-context final code review as required by executing-plans; fix material findings and rerun affected suites.
- [ ] Deliver actual tree, model/migration/seed/API inventory, setup commands and honest limitations.
