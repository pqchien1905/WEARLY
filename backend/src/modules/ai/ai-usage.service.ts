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
  }
  async reserve(
    userId: string,
    kind: 'STYLIST',
    key: string | undefined,
    hash: string,
    model: string,
  ) {
    if (!key || !isUUID(key, '4'))
      fail(400, 'INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be a UUID v4');
    await this.cleanup();
    return this.db.$transaction(
      async (tx) => {
        await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended('ai:usage:reservation', 0))::text`;
        // CURRENT_TIMESTAMP is the transaction start, potentially the previous
        // UTC day after waiting for the lock. Use one post-lock wall-clock value.
        const [{ now }] = await tx.$queryRaw<Array<{ now: Date }>>`
          SELECT clock_timestamp() AS now`;
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
        const day = today(now);
        const userUsed = await tx.aiUsage.count({
          where: { userId, kind, createdAt: { gte: day } },
        });
        const globalUsed = await tx.aiUsage.count({
          where: { kind, createdAt: { gte: day } },
        });
        const active = {
          status: 'PROCESSING' as const,
          deadlineAt: { gt: now },
        };
        const userActive = await tx.aiUsage.count({
          where: { ...active, userId },
        });
        const globalActive = await tx.aiUsage.count({ where: active });
        const estimate = this.config.getOrThrow<number>(
          'AI_STYLIST_ESTIMATE_VND',
        );
        const spent =
          (
            await tx.aiUsage.aggregate({
              where: { createdAt: { gte: day } },
              _sum: { estimatedCostVnd: true },
            })
          )._sum.estimatedCostVnd ?? new Prisma.Decimal(0);
        if (
          userUsed >=
            this.config.getOrThrow<number>('AI_STYLIST_USER_DAILY_LIMIT') ||
          globalUsed >=
            this.config.getOrThrow<number>('AI_STYLIST_GLOBAL_DAILY_LIMIT') ||
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
            createdAt: now,
            deadlineAt: new Date(now.getTime() + 30000),
            expiresAt: new Date(now.getTime() + 86400000),
          },
        });
        return { row, isNew: true };
      },
      { timeout: 15000 },
    );
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
  async ownedByKey(userId: string, kind: 'STYLIST', key: string) {
    await this.cleanup();
    const row = await this.db.aiUsage.findUnique({
      where: { userId_kind_requestKey: { userId, kind, requestKey: key } },
    });
    if (!row) throw new NotFoundException();
    return row;
  }
  async status(userId: string) {
    const rows = await this.db.aiUsage.aggregate({
      where: { userId, kind: 'STYLIST', createdAt: { gte: today() } },
      _count: true,
      _sum: { estimatedCostVnd: true },
    });
    const limit = this.config.getOrThrow<number>('AI_STYLIST_USER_DAILY_LIMIT');
    return {
      used: rows._count,
      limit,
      remaining: Math.max(0, limit - rows._count),
      estimatedUsedVnd: (
        rows._sum.estimatedCostVnd ?? new Prisma.Decimal(0)
      ).toString(),
      estimatedPerRequestVnd: String(
        this.config.getOrThrow<number>('AI_STYLIST_ESTIMATE_VND'),
      ),
      resetsAt: new Date(today().getTime() + 86400000).toISOString(),
      costIsEstimate: true,
    };
  }
}
