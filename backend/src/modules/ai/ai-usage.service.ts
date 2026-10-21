import {
  Injectable,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { isUUID } from 'class-validator';
import { PrismaService } from '../../database/prisma.service';
import { AiUsageStatus, Prisma } from '../../generated/prisma/client';
import { fail } from '../../common/errors';
const today = (now = new Date()) => {
  const date = new Date(now);
  date.setUTCHours(0, 0, 0, 0);
  return date;
};
@Injectable()
export class AiUsageService implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  constructor(
    private readonly db: PrismaService,
    private readonly config: ConfigService,
  ) {}
  onModuleInit() {
    this.timer = setInterval(() => {
      void this.cleanup().catch(() => undefined);
    }, 300000);
    this.timer.unref();
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }
  async cleanup() {
    const now = new Date();
    await this.db.aiUsage.updateMany({
      where: { status: 'RESERVED', deadlineAt: { lte: now } },
      data: {
        status: 'FAILED',
        errorCode: 'AI_QUEUE_EXPIRED',
        finishedAt: now,
      },
    });
    await this.db.aiUsage.updateMany({
      where: { status: 'PROCESSING', deadlineAt: { lte: now } },
      data: {
        status: 'UNKNOWN',
        errorCode: 'AI_OUTCOME_UNKNOWN',
        finishedAt: now,
      },
    });
    await this.db.aiUsage.updateMany({
      where: { expiresAt: { lte: now }, receipt: { not: Prisma.DbNull } },
      data: { receipt: Prisma.DbNull },
    });
    await this.db.aIJob.updateMany({
      where: {
        status: { in: ['PENDING', 'PROCESSING'] },
        usage: { status: 'UNKNOWN' },
      },
      data: { status: 'FAILED', errorCode: 'AI_OUTCOME_UNKNOWN' },
    });
    await this.db.aIJob.updateMany({
      where: {
        status: { in: ['PENDING', 'PROCESSING'] },
        usage: { status: 'FAILED', errorCode: 'AI_QUEUE_EXPIRED' },
      },
      data: { status: 'FAILED', errorCode: 'AI_QUEUE_EXPIRED' },
    });
  }
  async reserve(
    userId: string,
    kind: 'STYLIST' | 'TRY_ON',
    key: string | undefined,
    hash: string,
    model: string,
  ) {
    await this.cleanup();
    return this.db.$transaction(
      (tx) => this.reserveTx(tx, userId, kind, key, hash, model),
      { timeout: 15000 },
    );
  }
  async reserveTx(
    tx: Prisma.TransactionClient,
    userId: string,
    kind: 'STYLIST' | 'TRY_ON',
    key: string | undefined,
    hash: string,
    model: string,
  ) {
    if (!key || !isUUID(key, '4'))
      fail(400, 'INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be a UUID v4');
    await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended('ai:usage:reservation', 0))::text`;
    // One post-lock database wall clock, never transaction-start CURRENT_TIMESTAMP.
    const [{ now }] = await tx.$queryRaw<
      Array<{ now: Date }>
    >`SELECT clock_timestamp() AS now`;
    const prior = await tx.aiUsage.findUnique({
      where: { userId_kind_requestKey: { userId, kind, requestKey: key } },
    });
    if (prior) {
      if (prior.inputHash !== hash)
        fail(
          409,
          'IDEMPOTENCY_CONFLICT',
          'Request key already used with different input',
        );
      return { row: prior, isNew: false };
    }
    const day = today(now),
      prefix = kind === 'TRY_ON' ? 'AI_TRYON' : 'AI_STYLIST';
    const userUsed = await tx.aiUsage.count({
      where: { userId, kind, createdAt: { gte: day } },
    });
    const globalUsed = await tx.aiUsage.count({
      where: { kind, createdAt: { gte: day } },
    });
    const active = {
      status: { in: ['RESERVED', 'PROCESSING'] as AiUsageStatus[] },
      deadlineAt: { gt: now },
    };
    const userActive = await tx.aiUsage.count({ where: { ...active, userId } });
    const globalActive = await tx.aiUsage.count({ where: active });
    const estimate = this.config.getOrThrow<number>(prefix + '_ESTIMATE_VND');
    const spent =
      (
        await tx.aiUsage.aggregate({
          where: { createdAt: { gte: day } },
          _sum: { estimatedCostVnd: true },
        })
      )._sum.estimatedCostVnd ?? new Prisma.Decimal(0);
    if (
      userUsed >=
        this.config.getOrThrow<number>(prefix + '_USER_DAILY_LIMIT') ||
      globalUsed >=
        this.config.getOrThrow<number>(prefix + '_GLOBAL_DAILY_LIMIT') ||
      spent
        .plus(estimate)
        .gt(this.config.getOrThrow<number>('AI_GLOBAL_DAILY_ESTIMATE_VND'))
    )
      fail(429, 'AI_DAILY_LIMIT', 'Daily AI allowance reached');
    if (userActive >= 2 || globalActive >= 8)
      fail(429, 'AI_BUSY', 'Wait for current AI requests to finish');
    const row = await tx.aiUsage.create({
      data: {
        userId,
        kind,
        requestKey: key,
        inputHash: hash,
        model,
        estimatedCostVnd: estimate,
        status: kind === 'TRY_ON' ? 'RESERVED' : 'PROCESSING',
        createdAt: now,
        deadlineAt: new Date(
          now.getTime() + (kind === 'TRY_ON' ? 300000 : 30000),
        ),
        expiresAt: new Date(now.getTime() + 86400000),
      },
    });
    return { row, isNew: true };
  }
  async finish(
    id: string,
    status: AiUsageStatus,
    receipt?: Prisma.InputJsonValue,
    usage?: { inputTokens: number | null; outputTokens: number | null },
    errorCode?: string,
  ) {
    await this.db.aiUsage.updateMany({
      where: { id, status: 'PROCESSING', deadlineAt: { gt: new Date() } },
      data: {
        status,
        receipt: receipt ?? Prisma.DbNull,
        inputTokens: usage?.inputTokens,
        outputTokens: usage?.outputTokens,
        errorCode: errorCode ?? null,
        finishedAt: new Date(),
      },
    });
  }
  async ownedByKey(userId: string, kind: 'STYLIST' | 'TRY_ON', key: string) {
    await this.cleanup();
    const row = await this.db.aiUsage.findUnique({
      where: { userId_kind_requestKey: { userId, kind, requestKey: key } },
    });
    if (!row) throw new NotFoundException();
    return row;
  }
  async status(userId: string, kind: 'STYLIST' | 'TRY_ON' = 'STYLIST') {
    const prefix = kind === 'TRY_ON' ? 'AI_TRYON' : 'AI_STYLIST';
    const rows = await this.db.aiUsage.aggregate({
      where: { userId, kind, createdAt: { gte: today() } },
      _count: true,
      _sum: { estimatedCostVnd: true },
    });
    const limit = this.config.getOrThrow<number>(prefix + '_USER_DAILY_LIMIT');
    return {
      used: rows._count,
      limit,
      remaining: Math.max(0, limit - rows._count),
      estimatedUsedVnd: (
        rows._sum.estimatedCostVnd ?? new Prisma.Decimal(0)
      ).toString(),
      estimatedPerRequestVnd: String(
        this.config.getOrThrow<number>(prefix + '_ESTIMATE_VND'),
      ),
      resetsAt: new Date(today().getTime() + 86400000).toISOString(),
      costIsEstimate: true,
    };
  }
}
