ALTER TABLE "Order" ADD COLUMN "shippingMethod" VARCHAR(20) NOT NULL DEFAULT 'standard';
-- Previous checkout used exactly50000 for express (standard30000, or free).
UPDATE "Order" SET "shippingMethod" = 'express' WHERE "shipping" = 50000;
ALTER TABLE "Order" ADD CONSTRAINT "Order_shippingMethod_check" CHECK ("shippingMethod" IN ('standard', 'express'));
