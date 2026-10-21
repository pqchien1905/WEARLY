ALTER TYPE "AiUsageStatus" ADD VALUE 'RESERVED';
ALTER TABLE "ImageAsset" ADD COLUMN "requestKey" UUID;
CREATE UNIQUE INDEX "ImageAsset_userId_requestKey_key" ON "ImageAsset"("userId", "requestKey");
ALTER TABLE "AIJob" ADD COLUMN "usageId" UUID, ADD COLUMN "garmentRef" TEXT;
CREATE UNIQUE INDEX "AIJob_usageId_key" ON "AIJob"("usageId");
ALTER TABLE "AIJob" ADD CONSTRAINT "AIJob_usageId_fkey" FOREIGN KEY ("usageId") REFERENCES "AiUsage"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
