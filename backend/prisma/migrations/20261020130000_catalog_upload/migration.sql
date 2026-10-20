ALTER TYPE "AdminAuditAction" ADD VALUE 'PRODUCT_IMAGE_UPLOADED';
CREATE TABLE "CatalogAsset" (
  "id" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "actorId" UUID NOT NULL,
  "requestKey" UUID NOT NULL,
  "inputHash" VARCHAR(64) NOT NULL,
  "objectKey" TEXT NOT NULL,
  "sha256" VARCHAR(64) NOT NULL,
  "mimeType" TEXT NOT NULL,
  "size" INTEGER NOT NULL,
  "width" INTEGER NOT NULL,
  "height" INTEGER NOT NULL,
  "receipt" JSONB,
  "verifiedAt" TIMESTAMP(3),
  "deletedAt" TIMESTAMP(3),
  "purgedAt" TIMESTAMP(3),
  "purgeRetryAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "CatalogAsset_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "CatalogAsset_objectKey_key" ON "CatalogAsset"("objectKey");
CREATE UNIQUE INDEX "CatalogAsset_actorId_requestKey_key" ON "CatalogAsset"("actorId","requestKey");
CREATE INDEX "CatalogAsset_productId_idx" ON "CatalogAsset"("productId");
CREATE INDEX "CatalogAsset_verifiedAt_purgeRetryAt_createdAt_idx" ON "CatalogAsset"("verifiedAt","purgeRetryAt","createdAt");
