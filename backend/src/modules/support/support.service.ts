import { Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import { enqueueMail } from '../mail/outbox';
import {
  CreateSupportDto,
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
  replies: {
    orderBy: [{ createdAt: 'asc' as const }, { id: 'asc' as const }],
    select: {
      id: true,
      actorId: true,
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
  constructor(private readonly db: PrismaService) {}
  async create(dto: CreateSupportDto) {
    const payloadHash = hash([dto.name, dto.email, dto.message]);
    const replay = async () => {
      const row = await this.db.supportTicket.findUnique({
        where: { requestKey: dto.requestKey },
      });
      if (!row) return null;
      if (row.payloadHash !== payloadHash)
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
      return receipt(
        await this.db.supportTicket.create({ data: { ...dto, payloadHash } }),
      );
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
    const rows = await this.db.supportTicket.findMany({
      where: { status: dto.status },
      take: 31,
      ...(dto.cursor ? { cursor: { id: dto.cursor }, skip: 1 } : {}),
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      select: {
        id: true,
        name: true,
        email: true,
        status: true,
        version: true,
        createdAt: true,
        updatedAt: true,
        _count: { select: { replies: true } },
      },
    });
    return {
      items: rows.slice(0, 30),
      nextCursor: rows.length > 30 ? rows[29].id : null,
    };
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
      const ticket = await tx.supportTicket.findUnique({ where: { id } });
      if (!ticket) throw new NotFoundException();
      const prior = await tx.supportReply.findUnique({
        where: {
          ticketId_requestKey: { ticketId: id, requestKey: dto.requestKey },
        },
      });
      if (prior) {
        if (prior.payloadHash !== payloadHash)
          fail(
            409,
            'IDEMPOTENCY_CONFLICT',
            'Mã trả lời đã được dùng cho nội dung khác.',
          );
        return receipt(prior);
      }
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
        recipient: ticket.email,
        subject: 'WEARLY — Trả lời yêu cầu ' + id.slice(0, 8),
        body: `Xin chào ${ticket.name},\n\n${dto.message}\n\nMã yêu cầu: ${id}\nThư được lưu trong hộp thư local của hệ thống.`,
      });
      await tx.supportTicket.update({
        where: { id },
        data: { status: 'ANSWERED', version: { increment: 1 } },
      });
      await recordAdminActivity(tx, actorId, 'SUPPORT_REPLIED', reply.id);
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
      await recordAdminActivity(tx, actorId, 'SUPPORT_STATUS_CHANGED', id);
      return { id, status: row.status, version: row.version };
    });
  }
}
