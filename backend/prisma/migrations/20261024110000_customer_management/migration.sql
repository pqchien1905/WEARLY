ALTER TABLE "User" ADD COLUMN "deletedAt" TIMESTAMP(3);
ALTER TYPE "AdminAuditAction" ADD VALUE 'CUSTOMER_CREATED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'CUSTOMER_DELETED';
ALTER TABLE "User" ADD CONSTRAINT "User_deleted_inactive"
  CHECK ("deletedAt" IS NULL OR ("active" = false AND "role" = 'CUSTOMER'));
