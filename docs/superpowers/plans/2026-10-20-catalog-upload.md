# Catalog image upload

Grounding: audit A08 and the existing remote product gallery editor. Admins
currently supply public HTTPS URLs or bundled assets. Reuse its gallery
ordering/20-image limit, storage integration and image normalization.

## Chosen scope

- Upload one JPEG/PNG from the existing product editor after the product has
  been saved. Upload immediately adds one image to that product's persisted
  gallery. Keep URL/bundled-image entry and all existing metadata/SKU flows.
- Reuse8MiB,64–8192px,16MP, strict MIME/signature/decode and metadata stripping.
  ADMIN-only multipart endpoint; do not repurpose personal Try-On ImageAsset
  records or their24-hour expiry/consent workflow.
- Catalog photos are public assets, consistent with the existing public-URL
  gallery contract. Explain this before upload. Bucket remains private;
  a public API read route serves only verified CatalogAsset IDs. No object
  keys or credentials returned. Do not expose private-user upload IDs there.
- Stable relative media reference in gallery/order snapshots; Flutter resolves
  it against the configured API base. Serve validated raster bytes with fixed
  MIME, nosniff and bounded S3 retrieval. Existing images keep their URLs.
- Persist CatalogAsset reservation before S3, with random object key, normalized
  SHA256, input hash, metadata, product and actor IDs, request UUID, verification/
  failure/purge timestamps. A required idempotency key prevents duplicate
  gallery entries after an uncertain response; mismatched payload returns409.
- Finalize under asset/product locks, append at current position, enforce20
  slots and record PRODUCT_IMAGE_UPLOADED in the same DB transaction. Existing
  product gallery writes validate managed references belong to that product.
  Audit failure rolls back the gallery and leaves an identifiable failed object
  for cleanup. Never call storage from a serializable auto-retry callback.
- Use the existing Product `FOR UPDATE` row lock. The one owning upload
  request holds the asset lock during bounded PUT and finalization, then the
  product row lock for append. Pending replays do not acquire write ownership;
  failed reservations are terminal and cannot be reused. Cleanup takes the
  asset lock and revokes unverified reservations before delete. Periodically
  reconcile failed tombstones even after a prior successful delete, because a
  remote PUT accepted before a lost response can complete late. Verified
  records are never downgraded or included in this cleanup.
- Successful replay returns the immutable asset receipt; frontend fetches the
  current canonical gallery before replacing both local controllers/baseline.
  This remains correct when a previously uploaded image has since been removed.
- Retain verified catalog bytes when images are removed from a gallery or a
  product is hidden: order snapshots may still refer to them. No new automatic
  long-term deletion policy. Cleanup only unverified/failed upload reservations
  using bounded retries and the existing worker pattern.
- Editor requires saving pending gallery/metadata edits before uploading.
  Display progress, preview, errors and uncertain-result reload/reconciliation;
  stale completions after logout/navigation must not alter another form/session.
  Do not silently retry a multipart mutation with a new request key.

## Verification

Regression-first real PostgreSQL/MinIO tests: RBAC, format/size, metadata strip,
private bucket, public verified bytes, unknown/private IDs denied, idempotency,
parallel gallery limit, failed storage/audit, gallery validation, cleanup race
and preservation of verified assets. Flutter multipart/session, form/error and
media URL tests. Actual Chrome file picker/upload/save/reload/public image at
mobile/desktop. Full regression, migration/bootstrap, runtime and review.

Implementation choices may be tightened after security review; preserve current
architecture and do not invent promotion, settlement or provider business rules.
