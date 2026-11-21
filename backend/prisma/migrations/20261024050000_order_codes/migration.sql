-- A separate customer reference keeps existing UUID relations and links intact.
-- PostgreSQL sequences allocate distinct values even for concurrent checkouts.
CREATE SEQUENCE "order_code_seq" AS BIGINT;

CREATE FUNCTION next_order_code() RETURNS TEXT
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  value TEXT := upper(to_hex(nextval('order_code_seq')));
BEGIN
  RETURN 'WR' || lpad(value, greatest(6, length(value)), '0');
END;
$$;

ALTER TABLE "Order" ADD COLUMN "code" TEXT NOT NULL DEFAULT next_order_code();
CREATE UNIQUE INDEX "Order_code_key" ON "Order"("code");
