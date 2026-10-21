CREATE TYPE "AiUsageStatus" AS ENUM ('PROCESSING','COMPLETED','FAILED','UNKNOWN');
CREATE TABLE "AiUsage" (
  "id" UUID NOT NULL, "userId" UUID NOT NULL, "kind" VARCHAR(20) NOT NULL,
  "requestKey" UUID NOT NULL, "inputHash" VARCHAR(64) NOT NULL,
  "status" "AiUsageStatus" NOT NULL DEFAULT 'PROCESSING', "model" VARCHAR(80) NOT NULL,
  "estimatedCostVnd" DECIMAL(14,0) NOT NULL, "inputTokens" INTEGER, "outputTokens" INTEGER,
  "errorCode" VARCHAR(60), "receipt" JSONB, "deadlineAt" TIMESTAMP(3) NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL, "finishedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AiUsage_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "AiUsage_nonnegative" CHECK ("estimatedCostVnd">=0 AND ("inputTokens" IS NULL OR "inputTokens">=0) AND ("outputTokens" IS NULL OR "outputTokens">=0)),
  CONSTRAINT "AiUsage_kind" CHECK ("kind" IN ('STYLIST','TRY_ON'))
);
CREATE UNIQUE INDEX "AiUsage_userId_kind_requestKey_key" ON "AiUsage"("userId","kind","requestKey");
CREATE INDEX "AiUsage_createdAt_kind_idx" ON "AiUsage"("createdAt","kind");
CREATE INDEX "AiUsage_status_deadlineAt_idx" ON "AiUsage"("status","deadlineAt");
CREATE INDEX "AiUsage_expiresAt_idx" ON "AiUsage"("expiresAt");
