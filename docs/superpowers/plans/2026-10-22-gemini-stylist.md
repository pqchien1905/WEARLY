# Gemini Stylist implementation plan

> Execute inline with executing-plans and test-driven-development under the
> existing A-Z authorization. One independent milestone review and tested fix pass.

**Goal:** Authenticated customers get Gemini outfit suggestions grounded in current
catalog/stock/budget, with consent, bounded use, honest costs and safe retry.
**Spec:** docs/superpowers/specs/2026-10-21-local-completion-design.md, outcome6.
**BASE:**8997b62. Private image try-on follows in its own plan; not waived.
**Architecture:** Existing NestJS/PostgreSQL/Flutter. A bounded stateless Gemini
Interactions REST adapter, durable usage/idempotency receipt and remote Stylist UI.

## Decisions

- Builder call: configurable GEMINI_STYLIST_MODEL default gemini-3.5-flash-lite,
  GEMINI_API_KEY backend only. Fixed official v1/interactions URL, key in header,
  store:false, no tools/history/background, JSON response schema. One call per
  accepted request, no automatic provider retries. 20s includes reading body;
  1MiB text response cap, max_output_tokens2048. No raw provider error/log payload.
- Authenticate + consent:true + UUIDv4 Idempotency-Key. Prompt1..1000 chars,
  size1..20, style/color0..80, integer budget1..20millionVND. Query at most40 active
  in-stock variants matching size/color and budget, catalog text treated as data.
  Model returns1..4 unique SKUs; all extra fields/prose are discarded. Display text
  is server-controlled and derived from validated picks. Server rejects invented
  SKUs, duplicate products, total over budget, or changed stock/price/activation.
  Response includes chosen SKU/price, current catalog product and exact VND total.
- AiUsage stores user/kind/key/hash/status/model/estimatedCostVnd/token counts/
  deadline/result receipt; never stores raw prompt or input images. Only owner
  can read receipt. Completed stylist picks/constraints expire after24h and are erased
  on read/periodic cleanup; minimal usage remains for quota accounting.
- Global transaction lock serializes reservations; unique user/kind/key prevents
  duplicate calls. Default daily UTC limits:20 Stylist/user,200 global;2 active/user,
  8 global; estimated500VND/request,100000VND/day global budget. All accepted attempts
  count even failures/unknown outcomes. Values configurable with strict bounds.
  Display explicitly estimated provider cost, not customer payment or actual bill.
- Reserve PROCESSING with30s deadline before external call, outside transaction.
  Matching retry returns its receipt/status without re-calling. Conflicting payload
 409. Lost response can GET by request key; stale processing becomes UNKNOWN and
  never auto-resubmits. Terminal failure/new request requires explicit user action.
  Frontend POST may time out at15s; read same key to recover result, no second call.
- Review ruling: GET /ai/stylist/requests/latest returns the current owner's most
  recent unexpired receipt. Page entry/reload recovers using GET, blocks new requests
  on uncertain recovery, and never persists prompts or automatically POSTs again.
  Cost: it restores the latest request only; this is not an all-request history.
- Review ruling: one database clock_timestamp captured after the reservation lock
  determines quota day, createdAt and deadlines, avoiding transaction-start midnight
  drift. Cost: one additional bounded local query per reservation.
- Missing key reports configured:false and503 before reservation. No fake AI output.
  Provider live acceptance waits for user's backend/.env key; all other work proceeds.

## Review focus

1. Concurrent accepted requests cannot exceed per-user/global quota or spend estimate;
   lost replies/crashes/replays must not invoke Gemini twice for one key.
2. Model output cannot invent products/prices or bypass current stock/budget, including
   changed catalog during generation and JSON/prompt injection in catalog text.
3. Provider errors/slow streaming/redirects/oversized bodies are bounded and sanitized;
   no secret/prompt enters logs, responses, browser storage or Google stored history.
4. Account changes and late results cannot display another user's suggestions; UI
   retries recover the same request and new paid attempts are explicit.

## Task 1: Gemini adapter and grounded Stylist backend

Files: integrations/ai-providers/gemini.client.ts; modules/ai/{ai-usage.service,
stylist.service,stylist.controller,dto/stylist.dto}.ts; ai.module.ts;
config/env.validation.ts;.env.example;prisma/schema.prisma and migration
20261022050000_ai_usage; test/gemini-stylist.e2e-spec.ts; adapter unit spec.

Interfaces: GeminiClient.configured/model; generateJson(input:string,
schema:object):Promise<{value:unknown,inputTokens:number|null,outputTokens:number|null}>.
AiUsageService.reserve(userId,kind,key,hash,model): receipt + isNew; finish(id,status,
receipt?,usage?,errorCode?); ownedByKey(userId,kind,key); status(userId); cleanup().
StylistService.create(userId,key,dto), get(userId,key), status(userId).
Routes GET /ai/status; POST /ai/stylist/requests; GET /ai/stylist/requests/:key.
Receipt {id,requestKey,status,errorCode,createdAt,estimatedCostVnd,model,result?};
result {message,picks:[{sku,price,product}],total,currency:'VND'}.

- [x] RED unit: fixed URL/header/store:false/schema, valid completed response/usage,
  invalid JSON/schema/status/redirect, >1MiB, delayed body timeout, sanitized errors.
  RED real-PG/API: no-key status503/no reservation; auth/consent/key validation;
  grounded selection; malicious SKU/price/budget; catalog mutation while pending;
  parallel same-key calls once, changed-input409, limits under concurrency, owned
  receipt, lost reply recovery, expired processing UNKNOWN without provider retry.
  Run focused Jest; Expected FAIL missing adapter/routes.
- [x] Implement additive schema, testDB migrate/generate, adapter/quota/service/routes.
  Status response contains only configuration/model/usage, never key/raw errors.
- [x] Focused/full E2E + unit, lint/build sequentially; Expected PASS. Commit.

## Task 2: remote Stylist UI

Files: data/remote_stylist.dart; features/ai_stylist/remote_stylist_page.dart;
app/remote_route_gate.dart;test/remote_stylist_test.dart.
Interfaces: request DTO and receipts from Task1, existing ApiClient + catalog parser.
Page keyed by current user. Original demo remains usable in demo mode.

- [x] RED repository/widget tests: consent/configured status, pending/retry same UUID,
  safe account-change disposal, exact chosen SKU prices/total, no invented cart item,
  terminal failure explicit new request, quota/cost disclosure,375px no overflow.
  Run flutter focused test; Expected FAIL missing remote screen/repository.
- [x] Implement remote status/error/loading/retry, style/budget/size inputs, optional
  saved style profile, selected products and links, no demo scenario controls.
- [x] Full Flutter + analyze; Expected PASS. Commit.

## Task 3: browser acceptance, guide, review and migration

Files: tools/test-frontend-api.cjs --stylist;tools/verify-stylist-browser.cjs;
docs/GEMINI_LOCAL.md;docs/LOCAL_COMPLETION_PROGRESS.md.

- [x] Real Chrome/testDB with deterministic Gemini test adapter: login, consent,
  grounded result/price, retry after lost response without duplicate invocation,
  quota/error/new request, private receipt denial,375/1440. Explicitly label test
  adapter evidence; no live-provider success claimed. Expected PASS.
- [x] One independent review then one RED->GREEN fix pass; final182 E2E/54unit,
  395Flutter+2skips, lint/build/analyze and Chrome --stylist PASS.
  Verified business backup+migration+original-column fingerprints and read-only
  compiled smoke. Expected preserved data and200 public/401 private. Commit.
  Preserve A-Z goal ACTIVE for try-on, operations/SEO/providers and integration.

Final backup before-gemini-stylist-1792613302837.dump; business24->25, all40 original
table counts/column fingerprints preserved. Exactly one independent review and one
tested fix pass; see progress ledger for findings and tradeoffs. No live AI call.

Official references checked22Oct2026:
- https://ai.google.dev/api/interactions-api-v1
- https://ai.google.dev/gemini-api/docs/structured-output
- https://ai.google.dev/gemini-api/docs/models

Self-review: outcome6 Stylist covered in Tasks1–3; private try-on explicitly next.
Shared Task1 receipt/status names consumed unchanged by Task2 and3. No new external
account or production deployment assumed. Existing A-Z execution authority applies.
