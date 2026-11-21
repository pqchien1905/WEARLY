ALTER TABLE "SupportTicket" ADD COLUMN "userId" UUID;
ALTER TABLE "SupportTicket" ADD CONSTRAINT "SupportTicket_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "SupportTicket_userId_createdAt_id_idx" ON "SupportTicket"("userId", "createdAt", "id");
ALTER TABLE "SupportReply" ADD COLUMN "fromCustomer" BOOLEAN NOT NULL DEFAULT false;
