CREATE TYPE "AdminAuditAction" AS ENUM (
  'PRODUCT_CREATED', 'PRODUCT_UPDATED', 'SKU_CREATED', 'SKU_UPDATED',
  'CATEGORY_CREATED', 'CATEGORY_RENAMED', 'BRAND_CREATED', 'BRAND_RENAMED',
  'INVENTORY_ADJUSTED', 'ORDER_STATUS_CHANGED'
);

CREATE TABLE "AdminAuditEvent" (
  "id" UUID NOT NULL,
  "actorId" UUID NOT NULL,
  "action" "AdminAuditAction" NOT NULL,
  "targetId" UUID NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminAuditEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AdminAuditEvent_createdAt_id_idx"
  ON "AdminAuditEvent"("createdAt", "id");
