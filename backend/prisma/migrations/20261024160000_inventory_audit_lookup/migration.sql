-- Inventory history resolves audit links within one target and action.
CREATE INDEX "AdminAuditEvent_targetId_action_idx" ON "AdminAuditEvent"("targetId", "action");
