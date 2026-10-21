CREATE TYPE "ReturnStatus" AS ENUM ('REQUESTED','APPROVED','REJECTED','RECEIVED');
ALTER TYPE "AdminAuditAction" ADD VALUE 'ORDER_CANCELLED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'RETURN_DECIDED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'RETURN_RECEIVED';
CREATE TABLE "ReturnRequest" (
  "id" UUID NOT NULL PRIMARY KEY,
  "orderId" UUID NOT NULL REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "requestKey" UUID NOT NULL,
  "requestHash" VARCHAR(64) NOT NULL,
  "reason" VARCHAR(300) NOT NULL,
  "status" "ReturnStatus" NOT NULL DEFAULT 'REQUESTED',
  "amount" DECIMAL(14,0) NOT NULL CHECK ("amount" >= 0),
  "version" INTEGER NOT NULL DEFAULT 0 CHECK ("version" >= 0),
  "decisionNote" VARCHAR(300) NOT NULL DEFAULT '',
  "decidedBy" UUID,
  "decidedAt" TIMESTAMP(3),
  "receiptNote" VARCHAR(300) NOT NULL DEFAULT '',
  "receivedBy" UUID,
  "receivedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  UNIQUE ("orderId","requestKey")
);
CREATE INDEX "ReturnRequest_orderId_createdAt_idx" ON "ReturnRequest"("orderId","createdAt");
CREATE UNIQUE INDEX "ReturnRequest_open_order" ON "ReturnRequest"("orderId") WHERE "status" IN ('REQUESTED','APPROVED');
CREATE TABLE "ReturnItem" (
  "id" UUID NOT NULL PRIMARY KEY,
  "returnId" UUID NOT NULL REFERENCES "ReturnRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "orderItemId" UUID NOT NULL REFERENCES "OrderItem"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "quantity" INTEGER NOT NULL CHECK ("quantity" > 0),
  "amount" DECIMAL(14,0) NOT NULL CHECK ("amount" >= 0),
  UNIQUE ("returnId","orderItemId")
);
