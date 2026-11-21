ALTER TYPE "MailStatus" ADD VALUE 'HELD';
ALTER TYPE "MailStatus" ADD VALUE 'CANCELLED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'MAIL_UPDATED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'NEWSLETTER_UPDATED';
ALTER TYPE "AdminAuditAction" ADD VALUE 'NEWSLETTER_QUEUED';
ALTER TABLE "NewsletterSubscription" ADD COLUMN "unsubscribedAt" TIMESTAMP(3),
  ADD COLUMN "unsubscribeToken" UUID NOT NULL DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX "NewsletterSubscription_unsubscribeToken_key" ON "NewsletterSubscription"("unsubscribeToken");
CREATE TABLE "NewsletterCampaign" (
  id UUID PRIMARY KEY, "requestKey" UUID NOT NULL UNIQUE, subject VARCHAR(200) NOT NULL,
  body TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 0, "queuedAt" TIMESTAMP(3),
  "recipientCount" INTEGER NOT NULL DEFAULT 0, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL
);
ALTER TABLE "MailOutbox" ADD COLUMN "subscriptionId" UUID REFERENCES "NewsletterSubscription"(id) ON DELETE RESTRICT,
  ADD COLUMN "campaignId" UUID REFERENCES "NewsletterCampaign"(id) ON DELETE RESTRICT,
  ADD COLUMN "deliveryApprovedAt" TIMESTAMP(3);
CREATE INDEX "MailOutbox_subscriptionId_idx" ON "MailOutbox"("subscriptionId");
CREATE INDEX "MailOutbox_campaignId_idx" ON "MailOutbox"("campaignId");
