ALTER TABLE "ImageAsset"
  ADD COLUMN "width" INTEGER,
  ADD COLUMN "height" INTEGER,
  ADD COLUMN "sha256" TEXT,
  ADD COLUMN "consentAt" TIMESTAMP(3),
  ADD COLUMN "purgedAt" TIMESTAMP(3);
ALTER TABLE "ImageAsset" ADD CONSTRAINT "ImageAsset_dimensions_check"
  CHECK (("width" IS NULL AND "height" IS NULL) OR
    ("width" BETWEEN 64 AND 8192 AND "height" BETWEEN 64 AND 8192 AND "width"::BIGINT * "height" <= 16000000));
CREATE INDEX "ImageAsset_purgedAt_expiresAt_idx" ON "ImageAsset"("purgedAt", "expiresAt");
