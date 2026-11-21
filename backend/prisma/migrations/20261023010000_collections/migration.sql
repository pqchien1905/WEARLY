ALTER TYPE "AdminAuditAction" ADD VALUE 'COLLECTION_CREATED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'COLLECTION_UPDATED';

CREATE TABLE "StoreCollection" (
  "id" UUID NOT NULL,
  "slug" VARCHAR(100) NOT NULL,
  "title" VARCHAR(120) NOT NULL,
  "description" VARCHAR(1500) NOT NULL,
  "style" VARCHAR(100) NOT NULL,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "position" INTEGER NOT NULL DEFAULT 0 CHECK ("position" >= 0),
  "version" INTEGER NOT NULL DEFAULT 1 CHECK ("version" >= 1),
  "coverProductId" UUID,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "StoreCollection_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "StoreCollection_coverProductId_fkey" FOREIGN KEY ("coverProductId")
    REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "StoreCollection_slug_key" ON "StoreCollection"("slug");
CREATE UNIQUE INDEX "StoreCollection_style_key" ON "StoreCollection"("style");
CREATE INDEX "StoreCollection_active_position_id_idx" ON "StoreCollection"("active", "position", "id");
