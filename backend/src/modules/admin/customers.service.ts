import { Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import {
  AdminCustomersQueryDto,
  CreateCustomerDto,
  CustomerAdminAccessDto,
  DeleteCustomerDto,
  CustomerStatusDto,
  ResetCustomerPasswordDto,
  UpdateCustomerDto,
} from './dto/admin-customers.dto';
import { lockUser, transaction } from '../../common/transaction';
import { can } from '../../common/permissions';
import { fail } from '../../common/errors';
import {
  assertPhoneAvailable,
  lockProfileIdentity,
  normalizePhone,
} from '../users/profile-identity';
import { recordAdminActivity } from './audit';

const customerSelect = {
  id: true,
  username: true,
  name: true,
  email: true,
  phone: true,
  role: true,
  active: true,
  createdAt: true,
  updatedAt: true,
} as const;
const since30Days = () => new Date(Date.now() - 30 * 86400000);
@Injectable()
export class CustomersService {
  constructor(private readonly db: PrismaService) {}

  private async accessFields(
    tx: Prisma.TransactionClient,
    actorRole: string,
    dto: CustomerAdminAccessDto,
    id: string,
  ) {
    if (dto.adminAccess !== true) {
      if (dto.adminRole !== undefined || dto.username !== undefined)
        fail(
          400,
          'INVALID_ADMIN_ACCESS',
          'Bật quyền truy cập trang quản trị trước khi chọn vai trò và tên đăng nhập.',
        );
      return {};
    }
    if (!can(actorRole, 'staff.manage'))
      fail(
        403,
        'FORBIDDEN',
        'Chỉ Quản trị viên được cấp quyền truy cập trang quản trị.',
      );
    if (!dto.adminRole || !dto.username)
      fail(
        400,
        'INVALID_ADMIN_ACCESS',
        'Chọn vai trò và nhập tên đăng nhập quản trị.',
      );
    if (
      await tx.user.findFirst({
        where: {
          id: { not: id },
          username: { equals: dto.username, mode: 'insensitive' },
        },
        select: { id: true },
      })
    )
      fail(
        409,
        'USERNAME_ALREADY_EXISTS',
        'Tên đăng nhập đã được tài khoản khác sử dụng.',
      );
    return { role: dto.adminRole, username: dto.username };
  }

  private async identityConflict(
    error: unknown,
    dto: { email?: string; username?: string },
    id: string,
  ): Promise<never> {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === 'P2002'
    ) {
      if (
        dto.username &&
        (await this.db.user.findFirst({
          where: { id: { not: id }, username: dto.username },
          select: { id: true },
        }))
      )
        fail(
          409,
          'USERNAME_ALREADY_EXISTS',
          'Tên đăng nhập đã được tài khoản khác sử dụng.',
        );
      if (
        dto.email &&
        (await this.db.user.findFirst({
          where: { id: { not: id }, email: dto.email },
          select: { id: true },
        }))
      )
        fail(
          409,
          'EMAIL_ALREADY_EXISTS',
          'Email đã được tài khoản khác sử dụng.',
        );
    }
    throw error;
  }

  async create(actorId: string, dto: CreateCustomerDto) {
    const id = randomUUID();
    const passwordHash = await argon2.hash(dto.password, {
      type: argon2.argon2id,
      memoryCost: 19456,
      timeCost: 2,
      parallelism: 1,
    });
    try {
      return await transaction(this.db, async (tx) => {
        await lockProfileIdentity(tx);
        await lockUser(tx, actorId);
        await tx.$queryRaw`SELECT id FROM "User" WHERE id=${actorId}::uuid FOR UPDATE`;
        const actor = await tx.user.findUnique({ where: { id: actorId } });
        if (!actor?.active || !can(actor.role, 'customers.manage'))
          fail(403, 'FORBIDDEN', 'Không có quyền quản lý khách hàng.');
        const access = await this.accessFields(tx, actor.role, dto, id);
        if (
          await tx.user.findFirst({
            where: { email: { equals: dto.email, mode: 'insensitive' } },
            select: { id: true },
          })
        )
          fail(
            409,
            'EMAIL_ALREADY_EXISTS',
            'Email đã được tài khoản khác sử dụng.',
          );
        await assertPhoneAvailable(tx, id, dto.phone ?? '');
        const customer = await tx.user.create({
          data: {
            id,
            ...access,
            name: dto.name,
            email: dto.email,
            phone: dto.phone ?? '',
            passwordHash,
          },
          select: customerSelect,
        });
        await recordAdminActivity(
          tx,
          actorId,
          dto.adminAccess ? 'STAFF_UPDATED' : 'CUSTOMER_CREATED',
          id,
          {
            after: customer,
          },
        );
        return customer;
      });
    } catch (error) {
      return this.identityConflict(error, dto, id);
    }
  }

  remove(actorId: string, id: string, dto: DeleteCustomerDto) {
    return transaction(this.db, async (tx) => {
      await lockProfileIdentity(tx);
      for (const key of [...new Set([actorId, id])].sort()) {
        await lockUser(tx, key);
        await tx.$queryRaw`SELECT id FROM "User" WHERE id=${key}::uuid FOR UPDATE`;
      }
      const actor = await tx.user.findUnique({ where: { id: actorId } });
      if (!actor?.active || !can(actor.role, 'customers.manage'))
        fail(403, 'FORBIDDEN', 'Không có quyền quản lý khách hàng.');
      const current = await tx.user.findFirst({
        where: { id, role: 'CUSTOMER', deletedAt: null },
      });
      if (!current) throw new NotFoundException();
      if (
        current.updatedAt.toISOString() !==
        new Date(dto.expectedUpdatedAt).toISOString()
      )
        fail(
          409,
          'CUSTOMER_CONFLICT',
          'Thông tin khách hàng đã thay đổi. Hãy tải lại trước khi xóa.',
        );
      const deletedAt = new Date(
        Math.max(Date.now(), current.updatedAt.getTime() + 1),
      );
      await tx.user.update({
        where: { id },
        data: {
          active: false,
          deletedAt,
          updatedAt: deletedAt,
          staffVersion: { increment: 1 },
        },
      });
      await this.revokeAccess(tx, id);
      await recordAdminActivity(tx, actorId, 'CUSTOMER_DELETED', id, {
        before: current,
        after: { active: false, deletedAt },
      });
      return { id, deletedAt };
    });
  }

  async resetPassword(
    actorId: string,
    id: string,
    dto: ResetCustomerPasswordDto,
  ) {
    const passwordHash = await argon2.hash(dto.password, {
      type: argon2.argon2id,
      memoryCost: 19456,
      timeCost: 2,
      parallelism: 1,
    });
    return transaction(this.db, async (tx) => {
      for (const key of [...new Set([actorId, id])].sort()) {
        await lockUser(tx, key);
        await tx.$queryRaw`SELECT id FROM "User" WHERE id=${key}::uuid FOR UPDATE`;
      }
      const actor = await tx.user.findUnique({ where: { id: actorId } });
      if (!actor?.active || !can(actor.role, 'customers.manage'))
        fail(403, 'FORBIDDEN', 'Không có quyền quản lý khách hàng.');
      const current = await tx.user.findFirst({
        where: { id, role: 'CUSTOMER', deletedAt: null },
      });
      if (!current) throw new NotFoundException();
      if (
        current.updatedAt.toISOString() !==
        new Date(dto.expectedUpdatedAt).toISOString()
      )
        fail(
          409,
          'CUSTOMER_CONFLICT',
          'Thông tin khách hàng đã thay đổi. Hãy tải lại trước khi đặt lại mật khẩu.',
        );
      // Match the recovery queue's database clock so older queued requests
      // cannot create a usable recovery code after this password change.
      const [clock] = await tx.$queryRaw<
        { now: Date }[]
      >`SELECT clock_timestamp() AS now`;
      const updated = await tx.user.update({
        where: { id },
        data: {
          passwordHash,
          passwordChangedAt: clock.now,
          updatedAt: new Date(
            Math.max(clock.now.getTime(), current.updatedAt.getTime() + 1),
          ),
        },
        select: customerSelect,
      });
      await this.revokeAccess(tx, id);
      await recordAdminActivity(tx, actorId, 'STAFF_UPDATED', id, {
        before: { role: current.role, active: current.active },
        after: {
          role: updated.role,
          active: updated.active,
          passwordChanged: true,
        },
      });
      return updated;
    });
  }

  private async revokeAccess(tx: Prisma.TransactionClient, id: string) {
    const now = new Date();
    await tx.refreshToken.updateMany({
      where: { userId: id, revokedAt: null },
      data: { revokedAt: now },
    });
    await tx.passwordResetToken.updateMany({
      where: { userId: id, consumedAt: null },
      data: { consumedAt: now },
    });
    await tx.passwordResetCode.updateMany({
      where: { userId: id, consumedAt: null },
      data: { consumedAt: now },
    });
  }

  list(q: AdminCustomersQueryDto) {
    const search = (q.q ?? '').replace(/[\\%_]/g, '\\$&');
    const contains = { contains: search, mode: 'insensitive' as const };
    const where: Prisma.UserWhereInput = {
      role: 'CUSTOMER',
      deletedAt: null,
      ...(q.status ? { active: q.status === 'active' } : {}),
      ...(q.registered ? { createdAt: { gte: since30Days() } } : {}),
      ...(q.orders
        ? { orders: q.orders === 'has_orders' ? { some: {} } : { none: {} } }
        : {}),
      ...(search
        ? {
            OR: [
              { name: contains },
              { email: contains },
              { phone: contains },
              ...(/^[+\d\s().-]+$/.test(q.q ?? '') &&
              (q.q ?? '').replace(/\D/g, '').length >= 3
                ? [{ phone: { contains: normalizePhone(q.q!) } }]
                : []),
              ...(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
                q.q ?? '',
              )
                ? [{ id: q.q }]
                : []),
            ],
          }
        : {}),
    };
    const orderBy: Prisma.UserOrderByWithRelationInput[] =
      q.sort === 'oldest'
        ? [{ createdAt: 'asc' }, { id: 'asc' }]
        : q.sort === 'name_asc' || q.sort === 'name_desc'
          ? [{ name: q.sort === 'name_asc' ? 'asc' : 'desc' }, { id: 'asc' }]
          : q.sort === 'orders_desc'
            ? [
                { orders: { _count: 'desc' } },
                { createdAt: 'desc' },
                { id: 'desc' },
              ]
            : [{ createdAt: 'desc' }, { id: 'desc' }];
    return this.db.$transaction(
      async (tx) => {
        const items = await tx.user.findMany({
          where,
          select: { ...customerSelect, _count: { select: { orders: true } } },
          orderBy,
          take: q.limit,
          skip: (q.page - 1) * q.limit,
        });
        const total = await tx.user.count({ where });
        return { items, total, page: q.page, limit: q.limit };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  summary() {
    const since = since30Days();
    return this.db.$transaction(
      async (tx) => {
        const groups = await tx.user.groupBy({
          by: ['active'],
          where: { role: 'CUSTOMER', deletedAt: null },
          _count: { _all: true },
        });
        const active = groups.find((g) => g.active)?._count._all ?? 0;
        const inactive = groups.find((g) => !g.active)?._count._all ?? 0;
        const newCustomers = await tx.user.count({
          where: {
            role: 'CUSTOMER',
            deletedAt: null,
            createdAt: { gte: since },
          },
        });
        return {
          total: active + inactive,
          active,
          inactive,
          newCustomers,
          since: since.toISOString(),
          generatedAt: new Date().toISOString(),
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  detail(id: string) {
    return this.db.$transaction(
      async (tx) => {
        const customer = await tx.user.findFirst({
          where: { id, role: 'CUSTOMER', deletedAt: null },
          select: customerSelect,
        });
        if (!customer) throw new NotFoundException();
        const groups = await tx.order.groupBy({
          by: ['status'],
          where: { userId: id },
          _count: { _all: true },
          _sum: { total: true },
        });
        const paid = await tx.payment.aggregate({
          where: {
            order: { userId: id },
            status: { in: ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'] },
          },
          _sum: { amount: true },
        });
        const refunds = await tx.refund.aggregate({
          where: {
            payment: { order: { userId: id } },
            primary: true,
            status: 'SUCCEEDED',
          },
          _sum: { amount: true },
        });
        const legacyRefunds = await tx.payment.aggregate({
          where: {
            order: { userId: id },
            status: 'REFUNDED',
            refunds: { none: { primary: true, status: 'SUCCEEDED' } },
          },
          _sum: { amount: true },
        });
        const net = (paid._sum.amount ?? new Prisma.Decimal(0))
          .minus(refunds._sum.amount ?? 0)
          .minus(legacyRefunds._sum.amount ?? 0);
        const delivered = groups.find((g) => g.status === 'DELIVERED');
        return {
          ...customer,
          summary: {
            totalOrders: groups.reduce((n, g) => n + g._count._all, 0),
            deliveredOrders: delivered?._count._all ?? 0,
            deliveredValueVnd: delivered?._sum.total?.toFixed(0) ?? '0',
            netPaidVnd: net.toFixed(0),
            orderStatuses: Object.fromEntries(
              groups.map((g) => [g.status, g._count._all]),
            ),
          },
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  async update(
    actorId: string,
    id: string,
    dto: UpdateCustomerDto | CustomerStatusDto,
  ) {
    try {
      return await transaction(this.db, async (tx) => {
        await lockProfileIdentity(tx);
        for (const key of [...new Set([actorId, id])].sort()) {
          await lockUser(tx, key);
          await tx.$queryRaw`SELECT id FROM "User" WHERE id=${key}::uuid FOR UPDATE`;
        }
        const actor = await tx.user.findUnique({
          where: { id: actorId },
          select: { active: true, role: true },
        });
        if (!actor?.active || !can(actor.role, 'customers.manage'))
          fail(403, 'FORBIDDEN', 'Không có quyền quản lý khách hàng.');
        const current = await tx.user.findFirst({
          where: { id, role: 'CUSTOMER', deletedAt: null },
        });
        if (!current) throw new NotFoundException();
        if (
          current.updatedAt.toISOString() !==
          new Date(dto.expectedUpdatedAt).toISOString()
        )
          fail(
            409,
            'CUSTOMER_CONFLICT',
            'Thông tin khách hàng đã thay đổi. Hãy tải lại trước khi lưu.',
          );
        const statusChange = 'active' in dto;
        const data: Prisma.UserUpdateInput = {};
        if (statusChange) {
          data.active = dto.active;
        } else {
          Object.assign(data, await this.accessFields(tx, actor.role, dto, id));
          if (dto.name !== undefined) data.name = dto.name;
          if (dto.phone !== undefined) {
            await assertPhoneAvailable(tx, id, dto.phone);
            data.phone = dto.phone;
          }
          if (dto.email !== undefined) {
            if (
              await tx.user.findFirst({
                where: {
                  id: { not: id },
                  email: { equals: dto.email, mode: 'insensitive' },
                },
                select: { id: true },
              })
            )
              fail(
                409,
                'EMAIL_ALREADY_EXISTS',
                'Email đã được tài khoản khác sử dụng.',
              );
            data.email = dto.email;
          }
        }
        const changed = Object.entries(data).some(
          ([key, value]) =>
            current[
              key as 'name' | 'phone' | 'email' | 'active' | 'role' | 'username'
            ] !== value,
        );
        if (!changed)
          return tx.user.findUniqueOrThrow({
            where: { id },
            select: customerSelect,
          });
        const revoke =
          data.role !== undefined ||
          (data.email !== undefined && data.email !== current.email) ||
          (data.active !== undefined && data.active !== current.active);
        data.updatedAt = new Date(
          Math.max(Date.now(), current.updatedAt.getTime() + 1),
        );
        const permissionChange = statusChange || data.role !== undefined;
        if (permissionChange) data.staffVersion = { increment: 1 };
        const updated = await tx.user.update({
          where: { id },
          data,
          select: customerSelect,
        });
        if (revoke) {
          await this.revokeAccess(tx, id);
        }
        // The existing account-administration event already supports CUSTOMER
        // accounts via StaffService. Record changed-field flags, never contact data.
        await recordAdminActivity(tx, actorId, 'STAFF_UPDATED', id, {
          before: {
            role: current.role,
            active: current.active,
            staffVersion: current.staffVersion,
          },
          after: {
            role: updated.role,
            active: updated.active,
            staffVersion: current.staffVersion + (permissionChange ? 1 : 0),
            usernameChanged: updated.username !== current.username,
            nameChanged: updated.name !== current.name,
            emailChanged: updated.email !== current.email,
            phoneChanged: updated.phone !== current.phone,
          },
        });
        return updated;
      });
    } catch (error) {
      return this.identityConflict(error, 'active' in dto ? {} : dto, id);
    }
  }
}
