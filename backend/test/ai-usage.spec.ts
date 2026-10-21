import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { AiUsageService } from '../src/modules/ai/ai-usage.service';
import { PrismaService } from '../src/database/prisma.service';
import { Prisma } from '../src/generated/prisma/client';

it('accounts a reservation waiting across UTC midnight in the post-lock database day', async () => {
  const before = new Date('2026-10-21T23:59:59.900Z');
  const after = new Date('2026-10-22T00:00:00.100Z');
  // CURRENT_TIMESTAMP stays at transaction start even after the lock wait.
  jest
    .useFakeTimers({ doNotFake: ['nextTick', 'setImmediate'] })
    .setSystemTime(after);
  const rows: Array<{ createdAt: Date; estimatedCostVnd: number }> = [];
  const tx = {
    $queryRaw: jest.fn(async () => [{ now: after }]),
    aiUsage: {
      findUnique: async () => null,
      count: async ({ where }: { where: { createdAt?: { gte: Date } } }) =>
        where.createdAt
          ? rows.filter((r) => r.createdAt >= where.createdAt!.gte).length
          : 0,
      aggregate: async ({
        where,
      }: {
        where: { createdAt: { gte: Date } };
      }) => ({
        _sum: {
          estimatedCostVnd: new Prisma.Decimal(
            rows
              .filter((r) => r.createdAt >= where.createdAt.gte)
              .reduce((n, r) => n + r.estimatedCostVnd, 0),
          ),
        },
      }),
      create: async ({
        data,
      }: {
        data: { createdAt?: Date; estimatedCostVnd: number };
      }) => {
        const row = { ...data, createdAt: data.createdAt ?? before };
        rows.push(row);
        return row;
      },
    },
  };
  const db = {
    aiUsage: { updateMany: async () => ({ count: 0 }) },
    $transaction: async (work: (tx: unknown) => unknown) => work(tx),
  };
  const service = new AiUsageService(
    db as unknown as PrismaService,
    new ConfigService({
      AI_STYLIST_USER_DAILY_LIMIT: 1,
      AI_STYLIST_GLOBAL_DAILY_LIMIT: 100,
      AI_STYLIST_ESTIMATE_VND: 500,
      AI_GLOBAL_DAILY_ESTIMATE_VND: 500,
    }),
  );
  try {
    await service.reserve(
      randomUUID(),
      'STYLIST',
      randomUUID(),
      'hash',
      'gemini-fixture',
    );
    expect(rows[0].createdAt).toEqual(after);
    await expect(
      service.reserve(
        randomUUID(),
        'STYLIST',
        randomUUID(),
        'hash',
        'gemini-fixture',
      ),
    ).rejects.toMatchObject({ status: 429 });
    expect(rows).toHaveLength(1);
  } finally {
    jest.useRealTimers();
  }
});
