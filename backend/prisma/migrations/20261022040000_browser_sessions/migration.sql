ALTER TABLE "RefreshToken" ADD COLUMN "browserScope" VARCHAR(8);
ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_browserScope_check"
  CHECK ("browserScope" IS NULL OR "browserScope" IN ('customer', 'admin'));
