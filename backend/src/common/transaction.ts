import { Prisma } from '../generated/prisma/client';
import { PrismaService } from '../database/prisma.service';
export async function transaction<T>(
  db: PrismaService,
  run: (tx: Prisma.TransactionClient) => Promise<T>,
): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await db.$transaction(run, {
        isolationLevel: 'Serializable',
        timeout: 15000,
      });
    } catch (error) {
      if (
        !(error instanceof Prisma.PrismaClientKnownRequestError) ||
        error.code !== 'P2034' ||
        attempt >= 4
      )
        throw error;
      await new Promise((resolve) => setTimeout(resolve, 15 * (attempt + 1)));
    }
  }
}
export async function lockUser(tx: Prisma.TransactionClient, userId: string) {
  await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${userId}, 0))::text`;
}
