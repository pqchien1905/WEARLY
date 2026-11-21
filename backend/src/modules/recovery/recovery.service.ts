import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';
import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';
import * as argon2 from 'argon2';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { lockUser, transaction } from '../../common/transaction';
import { RECOVERY_QUEUE, RecoveryJob } from './recovery.queue';
import { RecoveryMailer } from './recovery.mailer';
import {
  RECOVERY_CODE_ATTEMPTS,
  RECOVERY_CODE_MINUTES,
  RECOVERY_GRANT_SECONDS,
} from './recovery.policy';
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
  private codeHash(userId: string, id: string, code: string) {
    return createHmac(
      'sha256',
      this.config.getOrThrow<string>('JWT_REFRESH_SECRET'),
    )
      .update(`wearly:password-recovery:${userId}:${id}:${code}`)
      .digest('hex');
  }
  async verifyCode(email: string, code: string) {
    this.enabled();
    const user = await this.db.user.findUnique({
      where: { email },
      select: { id: true },
    });
    const resetToken = randomBytes(32).toString('base64url');
    const accepted =
      user &&
      (await transaction(this.db, async (tx) => {
        await lockUser(tx, user.id);
        const current = await tx.passwordResetCode.findUnique({
          where: { userId: user.id },
          include: { user: true },
        });
        const now = await databaseNow(tx);
        if (
          !current ||
          !current.user.active ||
          current.user.role !== 'CUSTOMER' ||
          !current.deliveredAt ||
          current.consumedAt ||
          current.expiresAt <= now ||
          current.attempts >= RECOVERY_CODE_ATTEMPTS
        )
          return false;
        const valid = timingSafeEqual(
          Buffer.from(current.codeHash, 'hex'),
          Buffer.from(this.codeHash(user.id, current.id, code), 'hex'),
        );
        if (!valid) {
          // Commit failed guesses; throwing here would roll back the attempt budget.
          await tx.passwordResetCode.update({
            where: { id: current.id },
            data: {
              attempts: { increment: 1 },
              ...(current.attempts + 1 >= RECOVERY_CODE_ATTEMPTS
                ? { consumedAt: now }
                : {}),
            },
          });
          return false;
        }
        await tx.passwordResetCode.update({
          where: { id: current.id },
          data: { consumedAt: now },
        });
        await tx.passwordResetToken.updateMany({
          where: { userId: user.id, consumedAt: null },
          data: { consumedAt: now },
        });
        await tx.passwordResetToken.create({
          data: {
            userId: user.id,
            tokenHash: digest(resetToken),
            expiresAt: new Date(now.getTime() + RECOVERY_GRANT_SECONDS * 1000),
          },
        });
        return true;
      }));
    if (!accepted)
      throw new BadRequestException({
        code: 'RESET_CODE_INVALID',
        message:
          'Code is invalid, expired or no longer available. Request a new code.',
      });
    return { resetToken, expiresIn: RECOVERY_GRANT_SECONDS };
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
      candidate.user.role !== 'CUSTOMER' ||
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
        current.user.role !== 'CUSTOMER' ||
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
      await tx.passwordResetCode.updateMany({
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
  /** Signed-in password change for any role. Keeps the caller's session family. */
  async changePassword(
    userId: string,
    sessionId: string,
    currentPassword: string,
    password: string,
  ) {
    const user = await this.db.user.findUnique({ where: { id: userId } });
    if (
      !user?.active ||
      !(await argon2.verify(user.passwordHash, currentPassword))
    )
      throw new BadRequestException({
        code: 'CURRENT_PASSWORD_INVALID',
        message: 'Current password is incorrect',
      });
    if (currentPassword === password)
      throw new BadRequestException({
        code: 'PASSWORD_UNCHANGED',
        message: 'New password must differ from the current password',
      });
    const passwordHash = await argon2.hash(password, {
      type: argon2.argon2id,
      memoryCost: 19456,
      timeCost: 2,
      parallelism: 1,
    });
    await transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const current = await tx.user.findUnique({ where: { id: userId } });
      // Another change committed after verification: require a fresh attempt.
      if (!current?.active || current.passwordHash !== user.passwordHash)
        throw new ConflictException({
          code: 'PASSWORD_CHANGED_CONCURRENTLY',
          message: 'Password changed elsewhere. Sign in again and retry.',
        });
      const session = await tx.refreshToken.findFirst({
        where: { id: sessionId, userId, revokedAt: null },
      });
      if (!session) throw new UnauthorizedException();
      const now = await databaseNow(tx);
      await tx.user.update({
        where: { id: userId },
        data: { passwordHash, passwordChangedAt: now },
      });
      await tx.passwordResetToken.updateMany({
        where: { userId, consumedAt: null },
        data: { consumedAt: now },
      });
      await tx.passwordResetCode.updateMany({
        where: { userId, consumedAt: null },
        data: { consumedAt: now },
      });
      // Sign out every other device; the current session family stays valid.
      await tx.refreshToken.updateMany({
        where: { userId, revokedAt: null, NOT: { familyId: session.familyId } },
        data: { revokedAt: now },
      });
    });
    if (this.queue) {
      try {
        await this.bounded(
          this.queue.add('changed', { kind: 'changed', userId }),
        );
      } catch {
        this.logger.warn('RECOVERY_NOTIFICATION_UNAVAILABLE');
      }
    }
    return { changed: true };
  }
  async process(data: RecoveryJob) {
    if (data.kind === 'changed') {
      const user = await this.db.user.findUnique({
        where: { id: data.userId },
      });
      if (user?.active && user.role === 'CUSTOMER')
        await this.mailer.send(user.email);
      return;
    }
    const user = await this.db.user.findUnique({
      where: { email: data.email },
    });
    if (!user?.active || user.role !== 'CUSTOMER') return;
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const id = randomUUID();
    const created = await transaction(this.db, async (tx) => {
      await lockUser(tx, user.id);
      const current = await tx.user.findUnique({ where: { id: user.id } });
      const now = await databaseNow(tx);
      const requestedAt = new Date(data.requestedAt);
      if (
        !current?.active ||
        current.role !== 'CUSTOMER' ||
        current.email !== data.email ||
        !Number.isFinite(requestedAt.getTime()) ||
        (current.passwordChangedAt &&
          requestedAt <= current.passwordChangedAt) ||
        requestedAt > now ||
        now.getTime() - requestedAt.getTime() > 15 * 60 * 1000
      )
        return null;
      const previous = await tx.passwordResetCode.findUnique({
        where: { userId: current.id },
      });
      // A late queue retry must not replace a newer request or a delivered code.
      if (
        previous &&
        (previous.requestedAt > requestedAt ||
          (previous.requestedAt.getTime() === requestedAt.getTime() &&
            previous.deliveredAt))
      )
        return null;
      const challenge = {
        id,
        codeHash: this.codeHash(current.id, id, code),
        attempts: 0,
        requestedAt,
        createdAt: now,
        expiresAt: new Date(now.getTime() + RECOVERY_CODE_MINUTES * 60 * 1000),
        consumedAt: null,
        deliveredAt: null,
      };
      return tx.passwordResetCode.upsert({
        where: { userId: current.id },
        create: { ...challenge, userId: current.id },
        update: challenge,
      });
    });
    if (!created) return;
    try {
      await this.mailer.send(user.email, code);
      await this.db.passwordResetCode.updateMany({
        where: { id: created.id, consumedAt: null },
        data: { deliveredAt: await databaseNow(this.db) },
      });
    } catch {
      await this.db.passwordResetCode.updateMany({
        where: { id: created.id, consumedAt: null },
        data: { consumedAt: await databaseNow(this.db) },
      });
      throw new Error('MAIL_DELIVERY_FAILED');
    }
  }
  async purgeExpired() {
    await this.db.passwordResetCode.deleteMany({
      where: { expiresAt: { lte: await databaseNow(this.db) } },
    });
    await this.db.passwordResetToken.deleteMany({
      where: { expiresAt: { lte: await databaseNow(this.db) } },
    });
  }
}
