ALTER TABLE "ImageAsset" ADD COLUMN "purgeRetryAt" TIMESTAMP(3);
CREATE INDEX "ImageAsset_purgedAt_purgeRetryAt_idx" ON "ImageAsset"("purgedAt", "purgeRetryAt");
