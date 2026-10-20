import { AdminAuditAction, Prisma } from '../../generated/prisma/client';

/** Use only inside the transaction that performs the corresponding mutation. */
export async function recordAdminActivity(
  tx: Prisma.TransactionClient,
  actorId: string,
  action: AdminAuditAction,
  targetId: string,
): Promise<void> {
  await tx.adminAuditEvent.create({
    data: { actorId, action, targetId },
  });
}
