-- Reject unknown fees before the ordered shippingMethod backfill.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM "Order" WHERE "shipping" NOT IN (0, 30000, 50000)) THEN
    RAISE EXCEPTION 'Unknown historical shipping fee; reconcile its method before migration';
  END IF;
END $$;
