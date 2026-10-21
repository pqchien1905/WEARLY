CREATE TABLE "PaymentAttempt" (
  "id" UUID NOT NULL,
  "reference" VARCHAR(32) NOT NULL,
  "paymentId" UUID NOT NULL,
  "amount" DECIMAL(14,0) NOT NULL CHECK ("amount" > 0 AND "amount" <= 9999999999),
  "status" "PaymentStatus" NOT NULL DEFAULT 'PENDING',
  "ipAddress" VARCHAR(45) NOT NULL,
  "transactionNo" VARCHAR(15),
  "reviewRequired" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "lastQueryAt" TIMESTAMP(3),
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PaymentAttempt_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "PaymentAttempt_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "Payment"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "PaymentAttempt_reference_key" ON "PaymentAttempt"("reference");
CREATE UNIQUE INDEX "PaymentAttempt_transactionNo_key" ON "PaymentAttempt"("transactionNo");
CREATE INDEX "PaymentAttempt_paymentId_createdAt_idx" ON "PaymentAttempt"("paymentId", "createdAt");
