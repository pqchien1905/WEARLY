import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { transaction, lockUser } from '../../common/transaction';
import { fail } from '../../common/errors';
import { StaffQueryDto, UpdateStaffDto } from './staff.dto';
import { recordAdminActivity } from './audit';
const select = {
  id: true,
  name: true,
  email: true,
  username: true,
  role: true,
  active: true,
  staffVersion: true,
  createdAt: true,
} as const;
@Injectable()
export class StaffService {
  constructor(private readonly db: PrismaService) {}
  async list(q: StaffQueryDto) {
    const where = q.email
      ? { email: q.email }
      : { role: { not: 'CUSTOMER' as const } };
    return this.db.$transaction(
      async (tx) => ({
        items: await tx.user.findMany({
          where,
          select,
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          skip: (q.page - 1) * q.limit,
          take: q.limit,
        }),
        total: await tx.user.count({ where }),
        page: q.page,
        limit: q.limit,
      }),
      { isolationLevel: 'RepeatableRead' },
    );
  }
  update(actorId: string, id: string, dto: UpdateStaffDto) {
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended('staff-administration',0))::text`;
      for (const key of [...new Set([actorId, id])].sort()) {
        await lockUser(tx, key);
        await tx.$queryRaw`SELECT id FROM "User" WHERE id=${key}::uuid FOR UPDATE`;
      }
      const actor = await tx.user.findUnique({ where: { id: actorId } });
      if (!actor?.active || actor.role !== 'ADMIN')
        fail(403, 'FORBIDDEN', 'Administrator access is required');
      const current = await tx.user.findUnique({ where: { id }, select });
      if (!current) throw new NotFoundException();
      if (current.role === dto.role && current.active === dto.active)
        return current;
      if (current.staffVersion !== dto.expectedVersion)
        fail(
          409,
          'VERSION_CONFLICT',
          'Staff account changed; reload before editing',
        );
      if (
        current.active &&
        current.role === 'ADMIN' &&
        (!dto.active || dto.role !== 'ADMIN') &&
        (await tx.user.count({ where: { active: true, role: 'ADMIN' } })) <= 1
      )
        fail(409, 'LAST_ADMIN', 'Keep at least one active administrator');
      const updated = await tx.user.update({
        where: { id },
        data: {
          role: dto.role,
          active: dto.active,
          staffVersion: { increment: 1 },
        },
        select,
      });
      await tx.refreshToken.updateMany({
        where: { userId: id, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      await recordAdminActivity(tx, actorId, 'STAFF_UPDATED', id, {
        before: current,
        after: updated,
      });
      return updated;
    });
  }
}
