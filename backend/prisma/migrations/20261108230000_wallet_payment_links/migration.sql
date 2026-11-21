-- MoMo/ZaloPay issue the payment link through their API; keep it with the attempt.
ALTER TABLE "PaymentAttempt" ADD COLUMN "checkoutUrl" VARCHAR(2048);
