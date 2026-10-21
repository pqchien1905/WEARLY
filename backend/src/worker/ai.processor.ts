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
import { AiUsageService } from '../modules/ai/ai-usage.service';
import { GarmentReader } from '../integrations/ai-providers/garment-reader.service';
import { lockImage } from '../common/transaction';
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
    private readonly usage: AiUsageService,
    private readonly garments: GarmentReader,
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
    await this.usage.cleanup();
    const owned = await this.db.aIJob.findUnique({
      where: { id: job.data.id },
    });
    if (!owned || owned.status !== 'PENDING') return;
    if (!owned.usageId || !owned.garmentRef) {
      await this.db.aIJob.updateMany({
        where: { id: owned.id, status: 'PENDING' },
        data: { status: 'FAILED', errorCode: 'AI_REQUEST_LEGACY' },
      });
      return;
    }
    const row = await this.db.$transaction(
      async (tx) => {
        await lockImage(tx, owned.imageId);
        const current = await tx.aIJob.findUnique({
          where: { id: owned.id },
          include: { image: true, variant: true, usage: true },
        });
        if (!current || current.status !== 'PENDING' || !current.usageId)
          return null;
        const claimed = await tx.aiUsage.updateMany({
          where: {
            id: current.usageId,
            status: 'RESERVED',
            deadlineAt: { gt: new Date() },
          },
          data: {
            status: 'PROCESSING',
            deadlineAt: new Date(Date.now() + 150000),
          },
        });
        if (!claimed.count) return null;
        await tx.aIJob.update({
          where: { id: current.id },
          data: {
            status: 'PROCESSING',
            attempts: { increment: 1 },
            errorCode: null,
          },
        });
        return current;
      },
      { timeout: 20000 },
    );
    if (!row) return;
    const controller = new AbortController();
    let timer: NodeJS.Timeout | undefined;
    try {
      await Promise.race([
        (async () => {
          if (!this.provider.enabled)
            throw new UnrecoverableError('AI_PROVIDER_NOT_CONFIGURED');
          if (
            row.image.deletedAt ||
            row.image.purgedAt ||
            !row.image.verifiedAt ||
            !row.image.consentAt ||
            row.image.expiresAt <= new Date()
          )
            throw new UnrecoverableError('IMAGE_UNAVAILABLE');
          const bytes = await this.storage.readImage(row.image.objectKey);
          const garment = await this.garments.read(
            row.garmentRef!,
            row.variant.productId,
          );
          const stillOwned = await this.db.aIJob.findFirst({
            where: {
              id: row.id,
              status: 'PROCESSING',
              image: {
                deletedAt: null,
                purgedAt: null,
                expiresAt: { gt: new Date() },
              },
            },
          });
          if (!stillOwned || controller.signal.aborted)
            throw new UnrecoverableError('IMAGE_UNAVAILABLE');
          const eligible = await this.db.productVariant.findFirst({
            where: {
              id: row.variantId,
              active: true,
              inventory: { quantity: { gt: 0 } },
              product: { active: true, tryOnSupported: true },
            },
            select: { id: true },
          });
          if (!eligible) throw new UnrecoverableError('AI_CATALOG_CHANGED');
          if (!['image/jpeg', 'image/png'].includes(row.image.mimeType))
            throw new UnrecoverableError('IMAGE_UNAVAILABLE');
          const output = await this.provider.generate({
            jobId: row.id,
            sku: row.variant.sku,
            image: {
              bytes,
              contentType: row.image.mimeType as 'image/jpeg' | 'image/png',
            },
            garment,
            signal: controller.signal,
          });
          await this.db.$transaction(
            async (tx) => {
              await lockImage(tx, row.imageId);
              const latest = await tx.imageAsset.findUniqueOrThrow({
                where: { id: row.imageId },
              });
              const current = await tx.aIJob.findUniqueOrThrow({
                where: { id: row.id },
              });
              if (
                current.status !== 'PROCESSING' ||
                latest.deletedAt ||
                latest.purgedAt ||
                !latest.verifiedAt ||
                latest.expiresAt <= new Date()
              )
                throw new UnrecoverableError('IMAGE_UNAVAILABLE');
              if (controller.signal.aborted)
                throw new UnrecoverableError('PROVIDER_TIMEOUT');
              const objectKey = 'results/' + row.userId + '/' + row.id;
              await this.storage.putResult(
                objectKey,
                output.bytes,
                output.contentType,
              );
              if (controller.signal.aborted)
                throw new UnrecoverableError('PROVIDER_TIMEOUT');
              if (latest.expiresAt <= new Date())
                throw new UnrecoverableError('IMAGE_UNAVAILABLE');
              const finished = await tx.aiUsage.updateMany({
                where: {
                  id: row.usageId!,
                  status: 'PROCESSING',
                  deadlineAt: { gt: new Date() },
                },
                data: {
                  status: 'COMPLETED',
                  finishedAt: new Date(),
                  errorCode: null,
                  inputTokens: output.inputTokens,
                  outputTokens: output.outputTokens,
                },
              });
              if (!finished.count)
                throw new UnrecoverableError('AI_OUTCOME_UNKNOWN');
              const published = await tx.aIJob.updateMany({
                where: { id: row.id, status: 'PROCESSING' },
                data: { status: 'COMPLETED', errorCode: null },
              });
              if (!published.count)
                throw new UnrecoverableError('IMAGE_UNAVAILABLE');
              await tx.tryOnResult.upsert({
                where: { jobId: row.id },
                create: {
                  jobId: row.id,
                  objectKey,
                  expiresAt: latest.expiresAt,
                },
                update: {},
              });
            },
            { timeout: 20000 },
          );
        })(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            reject(new Error('PROVIDER_TIMEOUT'));
            controller.abort();
          }, 120000);
        }),
      ]);
    } catch (error) {
      const allowed = [
        'AI_PROVIDER_NOT_CONFIGURED',
        'IMAGE_UNAVAILABLE',
        'AI_GARMENT_UNAVAILABLE',
        'AI_CATALOG_CHANGED',
        'PROVIDER_TIMEOUT',
        'PROVIDER_ABORTED',
        'INVALID_PROVIDER_OUTPUT',
        'AI_PROVIDER_AUTH',
        'AI_PROVIDER_RATE_LIMIT',
        'AI_PROVIDER_UNAVAILABLE',
        'AI_OUTCOME_UNKNOWN',
      ];
      const known =
        error instanceof Error && allowed.includes(error.message)
          ? error.message
          : 'AI_PROVIDER_ERROR';
      const unknown = [
        'PROVIDER_TIMEOUT',
        'PROVIDER_ABORTED',
        'AI_OUTCOME_UNKNOWN',
      ].includes(known);
      await this.db.$transaction(
        async (tx) => {
          await tx.aiUsage.updateMany({
            where: { id: row.usageId!, status: 'PROCESSING' },
            data: {
              status: unknown ? 'UNKNOWN' : 'FAILED',
              errorCode: known,
              finishedAt: new Date(),
            },
          });
          await tx.aIJob.updateMany({
            where: { id: row.id, status: 'PROCESSING' },
            data: { status: 'FAILED', errorCode: known },
          });
        },
        { timeout: 20000 },
      );
      // Redis stores failedReason/stacktrace. Never forward private provider errors.
      throw new UnrecoverableError(known);
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
