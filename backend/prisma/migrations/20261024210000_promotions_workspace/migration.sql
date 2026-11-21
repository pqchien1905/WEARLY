ALTER TYPE "AdminAuditAction" ADD VALUE 'PROMOTION_DELETED';
CREATE INDEX "Coupon_createdAt_id_idx" ON "Coupon"("createdAt", "id");
CREATE INDEX "CouponRedemption_couponId_createdAt_id_idx" ON "CouponRedemption"("couponId", "createdAt", "id");
