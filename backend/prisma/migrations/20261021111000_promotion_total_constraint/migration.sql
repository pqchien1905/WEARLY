ALTER TABLE "Order" DROP CONSTRAINT "Order_total_valid";
ALTER TABLE "Order" ADD CONSTRAINT "Order_total_valid"
  CHECK ("subtotal" >= 0 AND "shipping" >= 0 AND "total" >= 0 AND "total" = "subtotal" + "shipping" - "discount");
