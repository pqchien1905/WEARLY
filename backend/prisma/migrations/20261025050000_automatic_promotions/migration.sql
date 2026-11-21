ALTER TABLE "Coupon" ADD COLUMN "name" VARCHAR(120) NOT NULL DEFAULT '',
  ADD COLUMN "application" VARCHAR(16) NOT NULL DEFAULT 'CODE',
  ADD COLUMN "scope" VARCHAR(16) NOT NULL DEFAULT 'ALL';
ALTER TABLE "Coupon" ADD CONSTRAINT "Coupon_application_check" CHECK ("application" IN ('CODE','AUTOMATIC')),
  ADD CONSTRAINT "Coupon_scope_check" CHECK ("scope" IN ('ALL','PRODUCTS'));
CREATE TABLE "CouponProduct" (
  "couponId" UUID NOT NULL REFERENCES "Coupon"("id") ON DELETE CASCADE,
  "productId" UUID NOT NULL REFERENCES "Product"("id") ON DELETE CASCADE,
  PRIMARY KEY ("couponId", "productId")
);
CREATE INDEX "CouponProduct_productId_idx" ON "CouponProduct"("productId");
ALTER TABLE "OrderItem" ADD COLUMN "originalUnitPrice" DECIMAL(14,0),
  ADD COLUMN "promotionName" TEXT,
  ADD COLUMN "automaticPromotionId" UUID REFERENCES "Coupon"("id") ON DELETE RESTRICT;
CREATE INDEX "Coupon_application_active_idx" ON "Coupon"("application", "active");
