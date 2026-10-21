# Private Gemini Try-on Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement
> inline, task by task, with test-driven-development and one independent review
> of this milestone. Existing A-Z authorization applies; no new approval gate.

**Goal:** Customers can upload a consented private photo, select a real garment,
request one bounded Gemini image edit, recover its job and delete private images.
**Architecture:** Extend existing uploads, AIJob/outbox/BullMQ, private MinIO and
AiUsage. One durable reservation per owned request key; a worker claims it once,
reads local private/catalog bytes and publishes only while image access is valid.
**Tech Stack:** Existing NestJS/Prisma/PostgreSQL/Redis/MinIO/Flutter; no new service.
**Spec:** docs/superpowers/specs/2026-10-21-local-completion-design.md, outcome6.
**BASE:**0ab3ad6. Stylist complete; operations/SEO/providers/integration remain next.

## Global Constraints

- Local only, Gemini only; secrets backend-only. Missing key means unavailable,
  never a synthetic result. Live-provider acceptance requires an observed response.
- Keep existing private image normalization: JPEG/PNG,8MiB,16MP,64..8192px, single
  frame; re-encode to remove metadata. Input/result access expires with photo24h.
- Explicit separate consent for upload and sending photo+garment to Google. UI says
  appearance is simulated, not a promise of fit. Never persist private bytes/URLs
  in browser storage or logs. Evict MemoryImage on replacement/deletion/disposal.
- One paid provider invocation per durable job, including concurrent workers,
  outbox replay, stalled queue and uncertain crash. Never automatically re-generate.
- Back up business data before additive migration; preserve original-column hashes.
  Test fixtures use *_test only. No builds/generation while full backend E2E runs.

## Decisions

- Configurable GEMINI_TRYON_MODEL=gemini-nano-banana-2.1. Fixed official stable
  /v1/interactions endpoint, x-goog-api-key header, store:false/background:false,
  no history/tools/remote image fetching. Inline normalized person+garment input;
  output image/jpeg,delivery:inline,image_size:1K,aspect_ratio:3:4.90s includes body;
  max16MiB JSON, max8MiB decoded output, strict base64/mime/completed response.
- Shared bounded Gemini transport function retains existing Stylist behavior/tests.
  TryOnInput switches from signed URLs to image/garment bytes with content types.
  Controlled prompt describes clothing replacement; catalog text is not instructions.
- GarmentReader accepts only a verified owned CatalogAsset reference or strict
  seed assets/images/basename under the real frontend/assets/images directory.
  No arbitrary URL, traversal, symlink escape, unbounded file or deleted media.
  Freeze selected garment reference with the job; worker revalidates it before use.
- AiUsage gains RESERVED. Default try-on quotas3/user/day,20global/day; estimate
  3000VND/request shares AI_GLOBAL_DAILY_ESTIMATE_VND with Stylist. All accepted
  attempts count, including failures;2active/user and8global include reserved jobs.
- AiUsage.reserveTx(tx,userId,kind,key,hash,model) uses the existing global lock and
  post-lock DB clock. AiService creates reservation+job+outbox in one transaction;
  locking order global quota then image. AIJob gains nullable unique usageId and
  garmentRef (additive for legacy rows). Keys are unique by owner/kind in AiUsage.
- Queued reservation deadline5min; worker atomically claims PENDING/RESERVED once,
  marks PROCESSING with150s deadline. Bounded worker120s total; adapter90s. Expired
  reservations fail AI_QUEUE_EXPIRED, stale processing becomes AI_OUTCOME_UNKNOWN;
  corresponding jobs settle FAILED. Old pending jobs without reservation cannot
  make paid calls (AI_REQUEST_LEGACY). Existing completed results remain readable
  while owned/unexpired. BullMQ options become1attempt; Redis delivery may retry,
  but durable claim prevents a second provider invocation.
- Upload Idempotency-Key is optional for compatibility, required by new UI. Add
  nullable requestKey on ImageAsset with unique owner/key; normalized sha256 binds
  the key. Matching verified replay returns original metadata, changed bytes409;
  pending/failed reservations never silently create another object. Own image list
  supplies recovery after reload. No raw input prompt needed for try-on.
- New authenticated byte routes replace private signed URLs in API responses:
  GET /uploads/images/:id/content and GET /ai/try-on/jobs/:id/result. Responses are
  private,no-store; owner/deletion/expiry rechecked under image lock. Metadata gives
  availability and relative content paths, never bearer URLs. New UI uses JWT
  ApiClient.getBytes with session-generation guards and bounded image validation.
  Already downloaded bytes cannot be recalled; local delete evicts UI caches and
  durable tombstones drive physical MinIO cleanup/retry.
- Routes: GET /ai/try-on/status; POST /ai/try-on/jobs with UUIDv4 Idempotency-Key;
  GET /ai/try-on/jobs (latest20 owned jobs), GET /ai/try-on/jobs/:id, GET result.
  Replay same key/body returns same job even when provider disabled; mismatch409.
  Current image owner/consent and active try-on SKU/stock required for new jobs.
- UI recovers server-owned images/jobs on entry and reload, GET polls2s up to60
  times then manual status refresh. Lost submission replies query job list using
  requestKey; same-key retry never starts another paid call. Terminal failures
  require explicit new request. Remote /virtual-try-on and /account/try-ons remain
  account-keyed; demo pages unchanged.

## Review Focus

1. Duplicate/stalled worker/crash after external send: never call Gemini again;
   settle unknown status with recoverable UI and honest consumed allowance.
2. Delete/expire/logout while bytes or generation are in flight: no new result
   publication or cross-account display; physical deletion retries late storage PUT.
3. Garment reference attacks: reject outside paths, symlinks, remote URLs, wrong
   owner/catalog assets and oversized images before a provider call.
4. Slow streaming, invalid/oversized/base64 image and provider error: bounded time,
   sanitized errors, no raw photo/key/URL in DB logs/Redis; usage remains consistent.
5. Lost upload/job responses and reload: recover owned state without creating a
   duplicate paid request; current SKU/consent/quotas remain enforced.

## Task 1: bounded image adapter and garment inputs

Files: create backend/src/integrations/ai-providers/{gemini-transport.ts,
gemini-tryon.provider.ts,garment-reader.service.ts}; modify gemini.client.ts,
try-on.provider.ts,config/env.validation.ts,.env.example; tests
backend/test/{gemini-tryon.spec.ts,garment-reader.spec.ts,gemini-client.spec.ts}.

Interfaces: GeminiTryOnProvider extends TryOnProvider, enabled/model/generate(input).
TryOnInput {jobId,sku,image:{bytes,contentType},garment:{bytes,contentType},signal};
TryOnOutput {bytes,contentType,inputTokens?,outputTokens?}. GarmentReader resolves
eligible reference metadata then read(ref,productId):Promise<NormalizedImage>.
Shared transport returns parsed bounded interaction JSON, using injected GEMINI_HTTP.

- [x] Write failing tests for fixed URL/inline2images/storefalse, completed image,
  abort/90s body timeout,16MiB envelope,8MiB image, badbase64/redirect/remote output,
  sanitized auth/rate-limit errors; garment seed/managed and escape/owner/deleted.
- [x] Run focused Jest; expected missing adapter failures. Implement adapter,
  transport extraction and strict environment defaults, keeping Stylist tests green.
- [x] Run npm test,lint/build;77unit PASS, lint/build clean. Commit deliverable.

## Task 2: private idempotent jobs, uploads and worker lifecycle

Files: schema.prisma and migration20261022060000_private_gemini_tryon;
modules/ai/{ai-usage.service,ai.service,ai.controller,ai.module}.ts;
modules/uploads/{uploads.service,uploads.controller,image-lifecycle.service}.ts;
worker/{ai.processor,worker.module}.ts;queues/ai.queue.ts; storage service as needed;
tests gemini-tryon.e2e-spec.ts,worker.e2e-spec.ts,uploads.e2e-spec.ts and AI fixtures.

Interfaces: Task1 provider/reader; reserveTx accepts STYLIST|TRY_ON, returns row/new;
existing Stylist reserve/status contract remains. Try-on status exposes configured,
used/limit/remaining/estimatedUsedVnd/estimatedPerRequestVnd/resetsAt/costIsEstimate.
Job receipt {id,requestKey,status,errorCode,imageId,sku,createdAt,expiresAt,
estimatedCostVnd,resultAvailable}; list {items}; image metadata existing fields plus
requestKey; content routes return image bytes. Job create body {imageId,sku,consent}.

- [ ] RED real-PG/Redis/storage tests: owner/auth/consent/config/currentSKU; concurrent
  same key1job/1usage/1outbox; differentbody409; daily/globalsharedlimits; duplicate
  worker once; crash/stale deadlines; upload lostreply/replay; private byte ownership,
  no signedURLs; deletion while queued/generating/publishing and failedphysicaldelete.
- [ ] Implement additive schema/testDB migration/generation, transactional quota and
  upload bindings, bounded durable worker and owned APIs. Update legacy worker retry
  tests to assert one paid attempt, sanitized errors and explicit terminal status.
- [ ] Focused then tools/test-backend.ps1 -WithWorker -WithStorage; npm test,lint/build
  sequentially. Expected all pass without external Gemini. Commit deliverable.

## Task 3: remote photo upload, generation and history UI

Files: frontend/lib/data/remote_tryon.dart;features/virtual_tryon/{remote_tryon_page,
remote_tryon_history}.dart;core/network/api_client.dart;app/remote_route_gate.dart;
tests remote_tryon_test.dart and private-byte/session tests.

Interfaces: Task2 status/jobs/images receipts and authenticated content routes;
ApiClient.getBytes(path) checks session generation through refresh/retry. Repository
uploads consented bytes with stable UUID; jobs create/get/list; delete source image
also removes its dependent results from visible history. Use existing catalog/SKU
models, file_selector and private_image eviction helper.

- [ ] RED tests for no key/consent, strict photo validation/replacement race,
  actualSKU selection, quota/cost display, upload/job lostresponse recovery, pending
  GET polling, failed explicitnewkey, reloadhistory, ownerchange/latebyte discard,
  delete during result load,375px layout and simulated-fit disclosure.
- [ ] Implement remote pages/repository and memory-only private previews with
  account-keyed lifecycle; preserve demo behavior and existing routes.
- [ ] Run focused/full Flutter and analyze; expected PASS. Commit deliverable.

## Task 4: browser proof, operator guide, review and safe migration

Files: tools/test-frontend-api.cjs --tryon;tools/verify-tryon-browser.cjs;
docs/GEMINI_LOCAL.md;docs/LOCAL_COMPLETION_PROGRESS.md.

- [ ] Chrome/testDB+Redis/MinIO+actual adapter with deterministic Gemini HTTP image
  reply: upload, explicitconsent, selectedgarment, onejob/result, lostreply/reload,
  owned history, unauthorizedbytes404, delete bothinput/output, quota/config/failure;
 375/1440 screenshots inspected. No real photo/external call in fixtures.
- [ ] One independent review of whole milestone; regrade then one RED->GREEN fix
  pass and relevant final suites. No additional review loop.
- [ ] Verified business backup, additive migration, all original-column hashes and
  compiled smoke. Update guide/ledger/checklist, commit and delete only own scratch.
  Keep A-Z active for operations/SEO/configured providers/final integration.

Official references checked22Oct2026: https://ai.google.dev/api/interactions-api-v1
and https://ai.google.dev/gemini-api/docs/image-generation . Stablev1 schema supports
inline image response; docs recommend configurable Nano Banana2.1 for multireference.
Self-review: outcome6 private image/garment/consent/quota/idempotency/deletion covered
by Tasks1-4; contracts align across API/worker/UI. Remaining outcomes9/10 not waived.
