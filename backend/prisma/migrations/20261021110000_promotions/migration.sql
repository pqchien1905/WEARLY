CREATE TYPE "CouponKind" AS ENUM ('FIXED','PERCENT');
ALTER TYPE "AdminAuditAction" ADD VALUE 'PROMOTION_CREATED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'PROMOTION_UPDATED';
ALTER TABLE "Order" ADD COLUMN "discount" DECIMAL(14,0) NOT NULL DEFAULT 0,
  ADD COLUMN "couponCode" TEXT,
  ADD CONSTRAINT "Order_discount_bounds" CHECK ("discount" >= 0 AND "discount" <= "subtotal");
ALTER TABLE "Coupon" ADD COLUMN "kind" "CouponKind" NOT NULL DEFAULT 'FIXED',
  ADD COLUMN "startsAt" TIMESTAMP(3),
  ADD COLUMN "minSubtotal" DECIMAL(14,0) NOT NULL DEFAULT 0,
  ADD COLUMN "maxDiscount" DECIMAL(14,0),
  ADD COLUMN "usageLimit" INTEGER,
  ADD COLUMN "perUserLimit" INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN "version" INTEGER NOT NULL DEFAULT 0,
  ADD CONSTRAINT "Coupon_limits" CHECK ("minSubtotal" >= 0 AND ("maxDiscount" IS NULL OR "maxDiscount" > 0) AND ("usageLimit" IS NULL OR "usageLimit" > 0) AND "perUserLimit" > 0);
CREATE TABLE "CouponRedemption" (
  "id" UUID NOT NULL PRIMARY KEY,
  "couponId" UUID NOT NULL REFERENCES "Coupon"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "orderId" UUID NOT NULL UNIQUE REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "userId" UUID NOT NULL,
  "discount" DECIMAL(14,0) NOT NULL CHECK ("discount" >= 0),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "releasedAt" TIMESTAMP(3)
);
CREATE INDEX "CouponRedemption_couponId_userId_releasedAt_idx" ON "CouponRedemption"("couponId", "userId", "releasedAt");
