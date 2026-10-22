# Store identity, policies and local HTML previews

Parent:2026-10-21-local-completion-design.md. User authorized A-Z completion,
local-only, Gemini, VNPay sandbox and simulated shipping. Optional identity question
has no answer; builder default WEARLY demo local, blank real contact details.
This is a bounded refinement of the approved storefront completeness outcome.

## Intent and constraints

Make published store information editable without changing order rules, remove
obsolete statements about unavailable AI/payment and expose readable product HTML
for local metadata inspection. Keep existing Flutter design and draft/publication
workflow. No production deployment, real legal assurances, invented contact data,
new merchant promises, indexing submission, or paid call.

## Publication contract

Add nullable JSON `details` and `publishedDetails` to StoreContent (migration27).
Typed details: name80, tagline160, email254, phone40, address300, about5000,
privacy5000, terms5000. All strings, trimmed, name nonblank; other blanks allowed,
nonblank email validated. Reject null/unknown fields/oversize. Whole details field
optional only for old clients; omission preserves stored draft details. Publication
copies details atomically with banner/policy and existing version guards/audit.
Existing rows are not rewritten. API normalizes null details to local defaults.
Public GET uses published fields only; unpublished singleton remains content:null.
Default name WEARLY, tagline Bản demo chạy local, contact blank. About/terms explain
local simulation; privacy accurately covers persistent sessions, server data,
explicit Gemini consent, private photo deletion and local support email. Shipping
policy remains existing policy field; default explains simulated delivery, sandbox,
COD reconciliation and return approval, without unsupported7day promise.

## Flutter surfaces

Extend published model and editor with details. Preserve dirty/version conflict,
lost-response refresh and account scope. Admin preview displays published details.
Use published name in BrandMark, published contact fields in footer/contact; hide
blank contact fields. About/privacy/terms/shipping pages show published plain text,
with truthful local defaults before first publication and explicit loading/error.
Add terms navigation. FAQ accurately distinguishes local simulator from Gemini
when configured; no old claims that reload logs out or AI is unavailable forever.
Keep demo-mode-specific behavior accurate. Fixed visible local-demo notice remains
even if an editor changes the store name. Reuse typography/tokens; check375/1440px.

## Local HTML metadata

Nest public routes under `/api/v1/storefront`: `products/:slug` returns escaped
HTML with title/description/canonical/OpenGraph and visible active product title,
description/variant prices, published store name and link to Flutter product page;
inactive/missing products return404. No private data, draft, user-specific price,
fake reviews, external image fetch, or inline script. Use existing ProductsService.
`sitemap.xml` lists active product preview URLs, bounded50000 with fail-closed limit;
UTF8 XML escaped. This is a local inspection sitemap, never submitted for indexing.
`robots.txt` explains noindex without blocking crawl (noindex requires crawl).
All preview responses have X-Robots-Tag:noindex,nofollow and no-store; HTML also
meta robots. Flutter index also noindex. Origin config `LOCAL_API_ORIGIN` default
http://127.0.0.1:3000 and `LOCAL_STORE_ORIGIN` default http://localhost:8080 must be
loopback HTTP(S) origins, no credentials/path/query/hash; never trust Host headers.
No rich-result guarantee or public SEO claim for this local application.

## Acceptance

Real PG content tests: nested validation, draft isolation, publish/re-publish,
legacy omission preservation, optimistic conflicts and denied staff permissions.
HTML tests: hostile text/Host, inactive/unknown product, published vs draft name,
absolute escaped sitemap and noindex. Flutter tests editor/fields/public defaults,
error and route visibility. Full lint/build/backend tests/Flutter analyze/tests;
native browser375/1440 and managed lifecycle smoke. Before business migration,
fresh native backup; additive migration preserves every preexisting field/row.
One final independent milestone review, one evidence-backed fix pass; no repeated
approval gate already covered by A-Z authorization. No unrelated redesign.

References: [Google noindex](https://developers.google.com/search/docs/crawling-indexing/block-indexing),
[sitemap conventions](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap).
