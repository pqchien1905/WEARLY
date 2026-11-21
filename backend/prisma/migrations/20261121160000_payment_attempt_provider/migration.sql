ALTER TABLE "PaymentAttempt" ADD COLUMN "provider" TEXT;

-- Recover the method used at creation from the first subsequent method change.
-- Old links also identify wallet origins. Leave ambiguous legacy rows unset.
UPDATE "PaymentAttempt" a SET "provider" = COALESCE(
  (SELECT CASE
    WHEN e.note LIKE '%: MoMo →%' THEN 'momo'
    WHEN e.note LIKE '%: ZaloPay →%' THEN 'zalopay'
    WHEN e.note LIKE '%: VNPay →%' THEN 'vnpay'
    END
   FROM "OrderEvent" e
   WHERE e."orderId" = p."orderId" AND e."createdAt" >= a."createdAt"
     AND e.note LIKE 'Khách đổi phương thức thanh toán:%'
   ORDER BY e."createdAt" ASC LIMIT 1),
  CASE WHEN a.reference ~ '^\d{6}_' THEN 'zalopay'
       WHEN a."checkoutUrl" LIKE '%momo.vn/%' THEN 'momo'
       WHEN p.provider IN ('momo','zalopay','vnpay') THEN p.provider END)
FROM "Payment" p WHERE p.id = a."paymentId";

-- Compatibility for older clients/fixtures; all application writes supply origin.
CREATE FUNCTION payment_attempt_origin() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.provider IS DISTINCT FROM NEW.provider THEN
    RAISE EXCEPTION 'Payment attempt provider is immutable';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.provider IS NULL THEN
    SELECT provider INTO NEW.provider FROM "Payment" WHERE id = NEW."paymentId"
      AND provider IN ('momo','zalopay','vnpay');
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER payment_attempt_origin BEFORE INSERT OR UPDATE ON "PaymentAttempt"
FOR EACH ROW EXECUTE FUNCTION payment_attempt_origin();
ALTER TYPE "AdminAuditAction" ADD VALUE 'PAYMENT_RECONCILED';
ALTER TABLE "OrderEvent" ALTER COLUMN "actorId" DROP NOT NULL;
