ALTER TYPE "AdminAuditAction" ADD VALUE 'COD_SETTLED';
CREATE TABLE "PaymentSettlement" (
  "id" UUID NOT NULL,
  "paymentId" UUID NOT NULL,
  "actorId" UUID NOT NULL,
  "amount" DECIMAL(14,0) NOT NULL,
  "reference" VARCHAR(100) NOT NULL,
  "settledAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PaymentSettlement_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "PaymentSettlement_amount_check" CHECK ("amount" > 0),
  CONSTRAINT "PaymentSettlement_reference_check" CHECK (length(trim("reference")) >= 3),
  CONSTRAINT "PaymentSettlement_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "Payment"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "PaymentSettlement_paymentId_key" ON "PaymentSettlement"("paymentId");
CREATE INDEX "PaymentSettlement_settledAt_idx" ON "PaymentSettlement"("settledAt");
