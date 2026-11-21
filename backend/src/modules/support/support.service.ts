import { Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import { enqueueMail } from '../mail/outbox';
import { ConfigService } from '@nestjs/config';
import {
  CreateSupportDto,
  CustomerFollowUpDto,
  CustomerSupportDto,
  CustomerSupportPageDto,
  ListSupportDto,
  ReplySupportDto,
  StatusSupportDto,
} from './support.dto';
const hash = (data: unknown) =>
  createHash('sha256').update(JSON.stringify(data)).digest('hex');
const receipt = (row: { id: string; createdAt: Date }) => ({
  id: row.id,
  createdAt: row.createdAt,
});
const select = {
  id: true,
  name: true,
  email: true,
  message: true,
  status: true,
  version: true,
  createdAt: true,
  updatedAt: true,
  user: {
    select: { id: true, name: true, email: true, deletedAt: true },
  },
  replies: {
    orderBy: [{ createdAt: 'asc' as const }, { id: 'asc' as const }],
    select: {
      id: true,
      actorId: true,
      fromCustomer: true,
      message: true,
      createdAt: true,
      mail: {
        select: {
          id: true,
          status: true,
          attempts: true,
          sentAt: true,
          lastError: true,
        },
      },
    },
  },
};
@Injectable()
export class SupportService {
  constructor(
    private readonly db: PrismaService,
    private readonly config: ConfigService,
  ) {}
  create(dto: CreateSupportDto) {
    return this.insert(
      { ...dto, payloadHash: hash([dto.name, dto.email, dto.message]) },
      dto.requestKey,
    );
  }
  /** A signed-in customer's ticket uses the account's name and email. */
  async createForCustomer(userId: string, dto: CustomerSupportDto) {
    const user = await this.db.user.findFirst({
      where: { id: userId, active: true, deletedAt: null },
      select: { name: true, email: true },
    });
    if (!user) throw new NotFoundException();
    return this.insert(
      {
        requestKey: dto.requestKey,
        message: dto.message,
        name: (user.name.trim() || user.email).slice(0, 100),
        email: user.email,
        userId,
        // Account details may change between retries; the request may not.
        payloadHash: hash(['account', userId, dto.message]),
      },
      dto.requestKey,
    );
  }
  private async insert(
    data: Prisma.SupportTicketUncheckedCreateInput,
    requestKey: string,
  ) {
    const replay = async () => {
      const row = await this.db.supportTicket.findUnique({
        where: { requestKey },
      });
      if (!row) return null;
      if (row.payloadHash !== data.payloadHash)
        fail(
          409,
          'IDEMPOTENCY_CONFLICT',
          'Mã gửi đã được dùng cho nội dung khác.',
        );
      return receipt(row);
    };
    const prior = await replay();
    if (prior) return prior;
    try {
      return receipt(await this.db.supportTicket.create({ data }));
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        const prior = await replay();
        if (prior) return prior;
      }
      throw error;
    }
  }
  async list(dto: ListSupportDto) {
    return this.db.$transaction(
      async (tx) => {
        const where: Prisma.SupportTicketWhereInput = {
          status: dto.status,
          ...(dto.userId ? { userId: dto.userId } : {}),
        };
        const total = await tx.supportTicket.count({ where });
        const limit = dto.limit ?? 10;
        const page = Math.min(
          dto.page ?? 1,
          Math.max(1, Math.ceil(total / limit)),
        );
        const rows = await tx.supportTicket.findMany({
          where,
          take: limit + 1,
          ...(dto.cursor
            ? { cursor: { id: dto.cursor }, skip: 1 }
            : { skip: (page - 1) * limit }),
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          select: {
            id: true,
            name: true,
            email: true,
            status: true,
            version: true,
            userId: true,
            createdAt: true,
            updatedAt: true,
            _count: { select: { replies: true } },
          },
        });
        return {
          items: rows.slice(0, limit),
          nextCursor: rows.length > limit ? rows[limit - 1].id : null,
          total,
          page,
          limit,
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  async detail(id: string) {
    const row = await this.db.supportTicket.findUnique({
      where: { id },
      select,
    });
    if (!row) throw new NotFoundException();
    return row;
  }
  async reply(actorId: string, id: string, dto: ReplySupportDto) {
    const payloadHash = hash([dto.expectedVersion, dto.message]);
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "SupportTicket" WHERE id=${id}::uuid FOR UPDATE`;
      const found = await tx.supportTicket.findUnique({
        where: { id },
        include: {
          user: { select: { name: true, email: true, deletedAt: true } },
        },
      });
      if (!found) throw new NotFoundException();
      const { user, ...ticket } = found;
      const prior = await tx.supportReply.findUnique({
        where: {
          ticketId_requestKey: { ticketId: id, requestKey: dto.requestKey },
        },
      });
      if (prior) {
        if (prior.payloadHash !== payloadHash || prior.fromCustomer)
          fail(
            409,
            'IDEMPOTENCY_CONFLICT',
            'Mã trả lời đã được dùng cho nội dung khác.',
          );
        return receipt(prior);
      }
      // Linked tickets follow the account's current email address.
      const contact = user && !user.deletedAt ? user : ticket;
      if (ticket.version !== dto.expectedVersion)
        fail(409, 'VERSION_CONFLICT', 'Yêu cầu đã thay đổi. Hãy tải lại.');
      if (ticket.status === 'CLOSED')
        fail(409, 'SUPPORT_CLOSED', 'Mở lại yêu cầu trước khi trả lời.');
      const reply = await tx.supportReply.create({
        data: {
          ticketId: id,
          actorId,
          requestKey: dto.requestKey,
          payloadHash,
          message: dto.message,
        },
      });
      await enqueueMail(tx, {
        eventKey: 'support-reply:' + reply.id,
        supportId: id,
        replyId: reply.id,
        recipient: contact.email,
        subject: 'WEARLY — Trả lời yêu cầu ' + id.slice(0, 8),
        body:
          `Xin chào ${contact.name || ticket.name},\n\n${dto.message}\n\nMã yêu cầu: ${id}\n` +
          (ticket.userId
            ? `Xem và trả lời trong tài khoản: ${this.config.getOrThrow<string>('LOCAL_STORE_ORIGIN')}/#/account/support/${id}\n`
            : '') +
          'WEARLY — Hỗ trợ khách hàng',
      });
      const updated = await tx.supportTicket.update({
        where: { id },
        data: { status: 'ANSWERED', version: { increment: 1 } },
      });
      await recordAdminActivity(tx, actorId, 'SUPPORT_REPLIED', reply.id, {
        before: ticket,
        after: updated,
      });
      return receipt(reply);
    });
  }
  mine(userId: string, q: CustomerSupportPageDto) {
    return this.db.$transaction(
      async (tx) => {
        const where = { userId };
        const [items, total] = await Promise.all([
          tx.supportTicket.findMany({
            where,
            skip: (q.page - 1) * q.limit,
            take: q.limit,
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            select: {
              id: true,
              message: true,
              status: true,
              createdAt: true,
              updatedAt: true,
              _count: { select: { replies: true } },
            },
          }),
          tx.supportTicket.count({ where }),
        ]);
        return { items, total, page: q.page, limit: q.limit };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  async mineDetail(userId: string, id: string) {
    // Staff identities, mail delivery state and the contact copy stay private.
    const row = await this.db.supportTicket.findFirst({
      where: { id, userId },
      select: {
        id: true,
        message: true,
        status: true,
        createdAt: true,
        updatedAt: true,
        replies: {
          orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
          select: {
            id: true,
            message: true,
            fromCustomer: true,
            createdAt: true,
          },
        },
      },
    });
    if (!row) throw new NotFoundException();
    return row;
  }
  async followUp(userId: string, id: string, dto: CustomerFollowUpDto) {
    const payloadHash = hash(['customer', dto.message]);
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "SupportTicket" WHERE id=${id}::uuid AND "userId"=${userId}::uuid FOR UPDATE`;
      const ticket = await tx.supportTicket.findFirst({
        where: { id, userId },
      });
      if (!ticket) throw new NotFoundException();
      const prior = await tx.supportReply.findUnique({
        where: {
          ticketId_requestKey: { ticketId: id, requestKey: dto.requestKey },
        },
      });
      if (prior) {
        if (prior.payloadHash !== payloadHash || !prior.fromCustomer)
          fail(
            409,
            'IDEMPOTENCY_CONFLICT',
            'Mã gửi đã được dùng cho nội dung khác.',
          );
        return receipt(prior);
      }
      if (ticket.status === 'CLOSED')
        fail(
          409,
          'SUPPORT_CLOSED',
          'Yêu cầu đã đóng. Hãy gửi một yêu cầu hỗ trợ mới.',
        );
      const reply = await tx.supportReply.create({
        data: {
          ticketId: id,
          actorId: userId,
          fromCustomer: true,
          requestKey: dto.requestKey,
          payloadHash,
          message: dto.message,
        },
      });
      // A new customer message puts the ticket back in the open queue.
      await tx.supportTicket.update({
        where: { id },
        data: { status: 'OPEN', version: { increment: 1 } },
      });
      return receipt(reply);
    });
  }
  async status(actorId: string, id: string, dto: StatusSupportDto) {
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "SupportTicket" WHERE id=${id}::uuid FOR UPDATE`;
      const ticket = await tx.supportTicket.findUnique({ where: { id } });
      if (!ticket) throw new NotFoundException();
      if (ticket.version !== dto.expectedVersion)
        fail(409, 'VERSION_CONFLICT', 'Yêu cầu đã thay đổi. Hãy tải lại.');
      if (ticket.status === dto.status)
        return { id, status: ticket.status, version: ticket.version };
      const row = await tx.supportTicket.update({
        where: { id },
        data: { status: dto.status, version: { increment: 1 } },
      });
      await recordAdminActivity(tx, actorId, 'SUPPORT_STATUS_CHANGED', id, {
        before: ticket,
        after: row,
      });
      return { id, status: row.status, version: row.version };
    });
  }
}
