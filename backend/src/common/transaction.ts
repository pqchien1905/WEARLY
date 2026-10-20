import { Prisma } from '../generated/prisma/client';
import { PrismaService } from '../database/prisma.service';
export function isTransactionConflict(error: unknown): boolean {
  if (error instanceof Prisma.PrismaClientKnownRequestError)
    return error.code === 'P2034';
  // Prisma's pg adapter can expose a commit-time conflict without wrapping it
  // in P2034. Only retry PostgreSQL's explicit serialization/deadlock outcomes.
  if (!(error instanceof Error) || error.name !== 'DriverAdapterError')
    return false;
  const cause = error.cause;
  return (
    typeof cause === 'object' &&
    cause !== null &&
    'kind' in cause &&
    cause.kind === 'TransactionWriteConflict' &&
    'originalCode' in cause &&
    ['40001', '40P01'].includes(String(cause.originalCode))
  );
}
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
      if (!isTransactionConflict(error) || attempt >= 4) throw error;
      await new Promise((resolve) => setTimeout(resolve, 15 * (attempt + 1)));
    }
  }
}
export async function lockUser(tx: Prisma.TransactionClient, userId: string) {
  await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${userId}, 0))::text`;
}
export async function lockImage(tx: Prisma.TransactionClient, imageId: string) {
  const key = 'image:' + imageId;
  await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${key}, 0))::text`;
}
