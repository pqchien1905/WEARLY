import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Job, Queue, UnrecoverableError, Worker } from 'bullmq';
import { PrismaService } from '../database/prisma.service';
import { TryOnProvider } from '../integrations/ai-providers/try-on.provider';
import { StorageService } from '../integrations/storage/storage.service';
import { AI_JOB_OPTIONS, AI_QUEUE } from '../queues/ai.queue';
@Injectable()
export class AiProcessor implements OnModuleInit, OnModuleDestroy {
  private queue!: Queue;
  private worker!: Worker;
  private timer?: NodeJS.Timeout;
  private dispatching = false;
  private readonly logger = new Logger('AIWorker');
  constructor(
    private readonly db: PrismaService,
    private readonly config: ConfigService,
    private readonly provider: TryOnProvider,
    private readonly storage: StorageService,
  ) {}
  onModuleInit() {
    const connection = {
      host: this.config.getOrThrow<string>('REDIS_HOST'),
      port: this.config.getOrThrow<number>('REDIS_PORT'),
      maxRetriesPerRequest: null,
    };
    const prefix = this.config.getOrThrow<string>('AI_QUEUE_PREFIX');
    this.queue = new Queue(AI_QUEUE, { connection, prefix });
    this.worker = new Worker(AI_QUEUE, (job) => this.process(job), {
      connection,
      prefix,
      concurrency: 2,
    });
    this.queue.on('error', () => this.logger.warn('QUEUE_UNAVAILABLE'));
    this.worker.on('error', () => this.logger.warn('WORKER_QUEUE_UNAVAILABLE'));
    this.timer = setInterval(() => {
      void this.dispatch();
    }, 2000);
    void this.dispatch();
  }
  async dispatch() {
    if (this.dispatching) return;
    this.dispatching = true;
    try {
      const pending = await this.db.outboxEvent.findMany({
        where: { publishedAt: null },
        take: 50,
        orderBy: { createdAt: 'asc' },
      });
      for (const event of pending) {
        // BullMQ jobId deduplicates retries after a crash between Redis and DB.
        await this.queue.add(
          'try-on',
          { id: event.jobId },
          { ...AI_JOB_OPTIONS, jobId: event.jobId },
        );
        await this.db.outboxEvent.update({
          where: { id: event.id },
          data: { publishedAt: new Date() },
        });
      }
    } catch {
      this.logger.warn('OUTBOX_RETRY_PENDING');
    } finally {
      this.dispatching = false;
    }
  }
  async process(job: Job<{ id: string }>) {
    const row = await this.db.aIJob.findUnique({
      where: { id: job.data.id },
      include: { image: true, variant: true },
    });
    if (!row || row.status === 'COMPLETED' || row.status === 'FAILED') return;
    await this.db.aIJob.update({
      where: { id: row.id },
      data: {
        status: 'PROCESSING',
        attempts: { increment: 1 },
        errorCode: null,
      },
    });
    let timer: NodeJS.Timeout | undefined;
    const controller = new AbortController();
    try {
      if (!this.provider.enabled)
        throw new UnrecoverableError('AI_PROVIDER_NOT_CONFIGURED');
      if (
        row.image.deletedAt ||
        !row.image.verifiedAt ||
        row.image.expiresAt <= new Date()
      )
        throw new UnrecoverableError('IMAGE_UNAVAILABLE');
      const imageUrl = await this.storage.signedRead(row.image.objectKey);
      const output = await Promise.race([
        this.provider.generate({
          jobId: row.id,
          imageUrl,
          sku: row.variant.sku,
          signal: controller.signal,
        }),
        new Promise<never>((_resolve, reject) => {
          timer = setTimeout(() => {
            controller.abort();
            reject(new Error('PROVIDER_TIMEOUT'));
          }, 60000);
        }),
      ]);
      const latest = await this.db.imageAsset.findUniqueOrThrow({
        where: { id: row.imageId },
      });
      if (latest.deletedAt || latest.expiresAt <= new Date())
        throw new UnrecoverableError('IMAGE_UNAVAILABLE');
      const objectKey = 'results/' + row.userId + '/' + row.id;
      await this.storage.putResult(objectKey, output.bytes, output.contentType);
      await this.db.$transaction(async (tx) => {
        await tx.tryOnResult.upsert({
          where: { jobId: row.id },
          create: { jobId: row.id, objectKey, expiresAt: row.image.expiresAt },
          update: {},
        });
        await tx.aIJob.update({
          where: { id: row.id },
          data: { status: 'COMPLETED', errorCode: null },
        });
      });
    } catch (error) {
      const final =
        error instanceof UnrecoverableError ||
        job.attemptsMade + 1 >= (job.opts.attempts ?? 1);
      const known =
        error instanceof Error &&
        [
          'AI_PROVIDER_NOT_CONFIGURED',
          'IMAGE_UNAVAILABLE',
          'PROVIDER_TIMEOUT',
          'INVALID_PROVIDER_OUTPUT',
        ].includes(error.message)
          ? error.message
          : 'AI_PROVIDER_ERROR';
      await this.db.aIJob.update({
        where: { id: row.id },
        data: { status: final ? 'FAILED' : 'PENDING', errorCode: known },
      });
      // BullMQ persists failedReason and stacktrace in Redis. Never forward a
      // provider exception that may contain credentials or signed image URLs.
      throw error instanceof UnrecoverableError
        ? new UnrecoverableError(known)
        : new Error(known);
    } finally {
      if (timer) clearTimeout(timer);
      controller.abort();
    }
  }
  async onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
    await this.worker?.close();
    await this.queue?.close();
  }
}
