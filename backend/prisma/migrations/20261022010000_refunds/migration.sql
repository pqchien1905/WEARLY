ALTER TYPE "PaymentStatus" ADD VALUE 'PARTIALLY_REFUNDED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'REFUND_CREATED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'REFUND_UPDATED';
CREATE TYPE "RefundStatus" AS ENUM ('REVIEW', 'PROCESSING', 'SUCCEEDED', 'FAILED');
CREATE TABLE "Refund" (
  "id" UUID NOT NULL,
  "paymentId" UUID NOT NULL,
  "attemptId" UUID,
  "primary" BOOLEAN NOT NULL,
  "requestKey" UUID NOT NULL,
  "payloadHash" CHAR(64) NOT NULL,
  "providerRequestId" VARCHAR(32) NOT NULL,
  "amount" DECIMAL(14,0) NOT NULL,
  "status" "RefundStatus" NOT NULL DEFAULT 'REVIEW',
  "reference" VARCHAR(100),
  "providerTransactionNo" VARCHAR(15),
  "actorId" UUID NOT NULL,
  "lastQueryAt" TIMESTAMP(3),
  "completedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "Refund_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "Refund_amount_check" CHECK ("amount" > 0),
  CONSTRAINT "Refund_source_check" CHECK (("attemptId" IS NULL AND "reference" IS NOT NULL AND length(trim("reference"))>=3) OR ("attemptId" IS NOT NULL AND "reference" IS NULL)),
  CONSTRAINT "Refund_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "Payment"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "Refund_attemptId_fkey" FOREIGN KEY ("attemptId") REFERENCES "PaymentAttempt"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "Refund_providerRequestId_key" ON "Refund"("providerRequestId");
CREATE UNIQUE INDEX "Refund_reference_key" ON "Refund"("reference");
CREATE UNIQUE INDEX "Refund_providerTransactionNo_key" ON "Refund"("providerTransactionNo");
CREATE UNIQUE INDEX "Refund_paymentId_requestKey_key" ON "Refund"("paymentId", "requestKey");
CREATE INDEX "Refund_paymentId_createdAt_idx" ON "Refund"("paymentId", "createdAt");
