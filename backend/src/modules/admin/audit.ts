import { AdminAuditAction, Prisma } from '../../generated/prisma/client';
import { auditSnapshot } from './audit-snapshot';

/** Use only inside the transaction that performs the corresponding mutation. */
export async function recordAdminActivity(
  tx: Prisma.TransactionClient,
  actorId: string,
  action: AdminAuditAction,
  targetId: string,
  snapshots?: { before?: unknown; after?: unknown },
): Promise<void> {
  await tx.adminAuditEvent.create({
    data: {
      actorId,
      action,
      targetId,
      details: snapshots
        ? {
            before: auditSnapshot(action, snapshots.before),
            after: auditSnapshot(action, snapshots.after),
          }
        : {},
    },
  });
}
