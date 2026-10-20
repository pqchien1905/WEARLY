ALTER TYPE "AdminAuditAction" ADD VALUE 'CONTENT_DRAFT_SAVED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'CONTENT_PUBLISHED';

CREATE TABLE "StoreContent" (
  "id" UUID NOT NULL,
  "key" VARCHAR(30) NOT NULL,
  "banner" VARCHAR(120) NOT NULL,
  "policy" VARCHAR(5000) NOT NULL,
  "version" INTEGER NOT NULL DEFAULT 1,
  "publishedBanner" VARCHAR(120),
  "publishedPolicy" VARCHAR(5000),
  "publishedVersion" INTEGER,
  "publishedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "StoreContent_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "StoreContent_key_check" CHECK ("key" = 'storefront'),
  CONSTRAINT "StoreContent_version_check" CHECK ("version" >= 1),
  CONSTRAINT "StoreContent_publication_check" CHECK (
    ("publishedBanner" IS NULL AND "publishedPolicy" IS NULL
      AND "publishedVersion" IS NULL AND "publishedAt" IS NULL)
    OR ("publishedBanner" IS NOT NULL AND "publishedPolicy" IS NOT NULL
      AND "publishedVersion" IS NOT NULL AND "publishedAt" IS NOT NULL
      AND "publishedVersion" >= 1 AND "publishedVersion" <= "version")
  )
);
CREATE UNIQUE INDEX "StoreContent_key_key" ON "StoreContent"("key");
