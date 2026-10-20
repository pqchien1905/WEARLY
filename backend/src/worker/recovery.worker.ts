import {
  Injectable,
  Logger,
  OnModuleInit,
  OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Worker } from 'bullmq';
import {
  RECOVERY_QUEUE,
  RecoveryJob,
} from '../modules/recovery/recovery.queue';
import { RecoveryService } from '../modules/recovery/recovery.service';
@Injectable()
export class RecoveryWorker implements OnModuleInit, OnModuleDestroy {
  private worker?: Worker<RecoveryJob>;
  private timer?: NodeJS.Timeout;
  private maintenance?: Promise<void>;
  private readonly logger = new Logger(RecoveryWorker.name);
  constructor(
    private readonly config: ConfigService,
    private readonly recovery: RecoveryService,
  ) {}
  onModuleInit() {
    if (this.config.get<string>('PASSWORD_RECOVERY_ENABLED') !== 'true') return;
    this.worker = new Worker<RecoveryJob>(
      RECOVERY_QUEUE,
      async (job) => {
        try {
          await this.recovery.process(job.data);
        } catch {
          throw new Error('RECOVERY_DELIVERY_FAILED');
        }
      },
      {
        prefix: this.config.getOrThrow<string>('AI_QUEUE_PREFIX'),
        connection: {
          host: this.config.getOrThrow<string>('REDIS_HOST'),
          port: this.config.getOrThrow<number>('REDIS_PORT'),
          maxRetriesPerRequest: null,
        },
        concurrency: 2,
      },
    );
    this.worker.on('error', () =>
      this.logger.warn('RECOVERY_WORKER_UNAVAILABLE'),
    );
    this.worker.on('failed', () =>
      this.logger.warn('RECOVERY_DELIVERY_FAILED'),
    );
    this.timer = setInterval(() => {
      if (this.maintenance) return;
      this.maintenance = this.recovery
        .purgeExpired()
        .catch(() => {
          this.logger.warn('RECOVERY_RETENTION_PENDING');
        })
        .finally(() => {
          this.maintenance = undefined;
        });
    }, 60000);
  }
  async onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
    await this.worker?.close();
    await this.maintenance;
  }
}
