import {
  BadRequestException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';
import { createHash, createHmac, randomBytes } from 'node:crypto';
import * as argon2 from 'argon2';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { lockUser, transaction } from '../../common/transaction';
import { RECOVERY_QUEUE, RecoveryJob } from './recovery.queue';
import { RecoveryMailer } from './recovery.mailer';
const digest = (token: string) =>
  createHash('sha256').update(token).digest('hex');
const invalid = () =>
  new BadRequestException({
    code: 'RESET_LINK_INVALID',
    message: 'Reset link is invalid or expired',
  });
export async function databaseNow(tx: Prisma.TransactionClient) {
  const [row] = await tx.$queryRaw<
    { now: Date }[]
  >`SELECT clock_timestamp() AS now`;
  return row.now;
}
@Injectable()
export class RecoveryService implements OnModuleInit, OnModuleDestroy {
  private queue?: Queue<RecoveryJob>;
  private readonly logger = new Logger(RecoveryService.name);
  constructor(
    private readonly db: PrismaService,
    private readonly config: ConfigService,
    private readonly mailer: RecoveryMailer,
  ) {}
  onModuleInit() {
    if (this.config.get<string>('PASSWORD_RECOVERY_ENABLED') !== 'true') return;
    this.queue = new Queue<RecoveryJob>(RECOVERY_QUEUE, {
      prefix: this.config.getOrThrow<string>('AI_QUEUE_PREFIX'),
      connection: {
        host: this.config.getOrThrow<string>('REDIS_HOST'),
        port: this.config.getOrThrow<number>('REDIS_PORT'),
        maxRetriesPerRequest: 1,
        enableOfflineQueue: false,
        connectTimeout: 2000,
        commandTimeout: 2000,
      },
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 2000 },
        removeOnComplete: true,
        removeOnFail: { age: 3600, count: 100 },
      },
    });
    this.queue.on('error', () =>
      this.logger.warn('RECOVERY_QUEUE_UNAVAILABLE'),
    );
  }
  async onModuleDestroy() {
    if (!this.queue) return;
    try {
      await this.bounded(this.queue.close());
    } catch {
      await this.queue.disconnect();
      this.logger.warn('RECOVERY_QUEUE_FORCED_CLOSE');
    }
  }
  private enabled() {
    if (!this.queue)
      throw new ServiceUnavailableException({
        code: 'RECOVERY_UNAVAILABLE',
        message: 'Password recovery unavailable',
      });
    return this.queue;
  }
  private async bounded<T>(operation: Promise<T>): Promise<T> {
    let timer: NodeJS.Timeout | undefined;
    try {
      return await Promise.race([
        operation,
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error('RECOVERY_QUEUE_TIMEOUT')),
            3000,
          );
        }),
      ]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
  async request(email: string) {
    const queue = this.enabled();
    // Same work for every valid email; account lookup only happens in the worker.
    const requestedAt = (await databaseNow(this.db)).toISOString();
    const id = createHmac(
      'sha256',
      this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
    )
      .update(email)
      .digest('hex');
    try {
      await this.bounded(
        queue.add(
          'request',
          { kind: 'request', email, requestedAt },
          { deduplication: { id, ttl: 60000 } },
        ),
      );
    } catch {
      throw new ServiceUnavailableException({
        code: 'RECOVERY_UNAVAILABLE',
        message: 'Password recovery unavailable',
      });
    }
    return { accepted: true };
  }
  async reset(token: string, password: string) {
    this.enabled();
    const hash = digest(token);
    const candidate = await this.db.passwordResetToken.findUnique({
      where: { tokenHash: hash },
      include: { user: true },
    });
    if (
      !candidate ||
      candidate.consumedAt ||
      !candidate.user.active ||
      candidate.expiresAt <= (await databaseNow(this.db))
    )
      throw invalid();
    const passwordHash = await argon2.hash(password, {
      type: argon2.argon2id,
      memoryCost: 19456,
      timeCost: 2,
      parallelism: 1,
    });
    await transaction(this.db, async (tx) => {
      await lockUser(tx, candidate.userId);
      const current = await tx.passwordResetToken.findUnique({
        where: { tokenHash: hash },
        include: { user: true },
      });
      const now = await databaseNow(tx);
      if (
        !current ||
        current.consumedAt ||
        !current.user.active ||
        current.expiresAt <= now
      )
        throw invalid();
      await tx.user.update({
        where: { id: current.userId },
        data: { passwordHash, passwordChangedAt: now },
      });
      await tx.passwordResetToken.updateMany({
        where: { userId: current.userId, consumedAt: null },
        data: { consumedAt: now },
      });
      await tx.refreshToken.updateMany({
        where: { userId: current.userId, revokedAt: null },
        data: { revokedAt: now },
      });
    });
    try {
      await this.bounded(
        this.queue!.add('changed', {
          kind: 'changed',
          userId: candidate.userId,
        }),
      );
    } catch {
      // A notification failure must never undo a committed password change.
      this.logger.warn('RECOVERY_NOTIFICATION_UNAVAILABLE');
    }
    return { changed: true };
  }
  async process(data: RecoveryJob) {
    if (data.kind === 'changed') {
      const user = await this.db.user.findUnique({
        where: { id: data.userId },
      });
      if (user?.active) await this.mailer.send(user.email);
      return;
    }
    const user = await this.db.user.findUnique({
      where: { email: data.email },
    });
    if (!user?.active) return;
    const token = randomBytes(32).toString('base64url');
    const created = await transaction(this.db, async (tx) => {
      await lockUser(tx, user.id);
      const current = await tx.user.findUnique({ where: { id: user.id } });
      const now = await databaseNow(tx);
      const requestedAt = new Date(data.requestedAt);
      if (
        !current?.active ||
        !Number.isFinite(requestedAt.getTime()) ||
        (current.passwordChangedAt &&
          requestedAt <= current.passwordChangedAt) ||
        requestedAt > now ||
        now.getTime() - requestedAt.getTime() > 15 * 60 * 1000
      )
        return null;
      return tx.passwordResetToken.create({
        data: {
          userId: current.id,
          tokenHash: digest(token),
          expiresAt: new Date(now.getTime() + 15 * 60 * 1000),
        },
      });
    });
    if (!created) return;
    try {
      await this.mailer.send(user.email, token);
    } catch {
      await this.db.passwordResetToken.updateMany({
        where: { id: created.id, consumedAt: null },
        data: { consumedAt: await databaseNow(this.db) },
      });
      throw new Error('MAIL_DELIVERY_FAILED');
    }
  }
  async purgeExpired() {
    await this.db.passwordResetToken.deleteMany({
      where: { expiresAt: { lte: await databaseNow(this.db) } },
    });
  }
}
