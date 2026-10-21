ALTER TYPE "AdminAuditAction" ADD VALUE 'SUPPORT_REPLIED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'SUPPORT_STATUS_CHANGED';
CREATE TYPE "SupportStatus" AS ENUM ('OPEN', 'ANSWERED', 'CLOSED');
CREATE TYPE "MailStatus" AS ENUM ('PENDING', 'PROCESSING', 'SENT', 'FAILED');
CREATE TABLE "SupportTicket" (
 "id" UUID NOT NULL, "requestKey" UUID NOT NULL, "payloadHash" CHAR(64) NOT NULL,
 "name" VARCHAR(100) NOT NULL, "email" VARCHAR(254) NOT NULL, "message" VARCHAR(3000) NOT NULL,
 "status" "SupportStatus" NOT NULL DEFAULT 'OPEN', "version" INTEGER NOT NULL DEFAULT 0,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
 CONSTRAINT "SupportTicket_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "SupportTicket_requestKey_key" ON "SupportTicket"("requestKey");
CREATE INDEX "SupportTicket_status_createdAt_id_idx" ON "SupportTicket"("status","createdAt","id");
CREATE TABLE "SupportReply" (
 "id" UUID NOT NULL, "ticketId" UUID NOT NULL, "actorId" UUID NOT NULL,
 "requestKey" UUID NOT NULL, "payloadHash" CHAR(64) NOT NULL, "message" VARCHAR(3000) NOT NULL,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "SupportReply_pkey" PRIMARY KEY ("id"),
 CONSTRAINT "SupportReply_ticketId_fkey" FOREIGN KEY ("ticketId") REFERENCES "SupportTicket"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "SupportReply_ticketId_requestKey_key" ON "SupportReply"("ticketId","requestKey");
CREATE INDEX "SupportReply_ticketId_createdAt_id_idx" ON "SupportReply"("ticketId","createdAt","id");
CREATE TABLE "MailOutbox" (
 "id" UUID NOT NULL, "eventKey" VARCHAR(160) NOT NULL, "recipient" VARCHAR(254) NOT NULL,
 "subject" VARCHAR(200) NOT NULL, "body" TEXT NOT NULL, "orderId" UUID, "supportId" UUID, "replyId" UUID,
 "status" "MailStatus" NOT NULL DEFAULT 'PENDING', "attempts" INTEGER NOT NULL DEFAULT 0,
 "leaseToken" UUID, "leaseUntil" TIMESTAMP(3), "nextAttemptAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 "sentAt" TIMESTAMP(3), "lastError" VARCHAR(40),
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
 CONSTRAINT "MailOutbox_pkey" PRIMARY KEY ("id"),
 CONSTRAINT "MailOutbox_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "MailOutbox_supportId_fkey" FOREIGN KEY ("supportId") REFERENCES "SupportTicket"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "MailOutbox_replyId_fkey" FOREIGN KEY ("replyId") REFERENCES "SupportReply"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "MailOutbox_attempts_check" CHECK ("attempts" BETWEEN 0 AND 5)
);
CREATE UNIQUE INDEX "MailOutbox_eventKey_key" ON "MailOutbox"("eventKey");
CREATE UNIQUE INDEX "MailOutbox_replyId_key" ON "MailOutbox"("replyId");
CREATE INDEX "MailOutbox_status_nextAttemptAt_idx" ON "MailOutbox"("status","nextAttemptAt");
CREATE INDEX "MailOutbox_status_leaseUntil_idx" ON "MailOutbox"("status","leaseUntil");
CREATE INDEX "MailOutbox_orderId_createdAt_idx" ON "MailOutbox"("orderId","createdAt");
CREATE INDEX "MailOutbox_supportId_createdAt_idx" ON "MailOutbox"("supportId","createdAt");
