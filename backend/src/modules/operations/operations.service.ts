import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OperationsProbes } from './operations.probes';

@Injectable()
export class OperationsService {
  constructor(
    private readonly config: ConfigService,
    private readonly probes: OperationsProbes,
  ) {}
  async snapshot() {
    const [db, redis, storage, mail] = await Promise.allSettled([
      this.probes.database(),
      this.probes.redis(),
      this.probes.storage(),
      this.probes.mail(),
    ]);
    return {
      observedAt: new Date().toISOString(),
      database:
        db.status === 'fulfilled'
          ? db.value.database
          : {
              status: 'unavailable' as const,
              schemaReady: null,
              migrations: null,
            },
      work: db.status === 'fulfilled' ? db.value.work : null,
      redis:
        redis.status === 'fulfilled'
          ? { status: 'ok' as const, queues: redis.value.queues }
          : { status: 'unavailable' as const, queues: null },
      worker:
        redis.status === 'fulfilled'
          ? redis.value.worker
          : { status: 'unavailable' as const, lastAt: null },
      storage:
        storage.status === 'fulfilled'
          ? storage.value
          : { status: 'unavailable' as const },
      mail:
        mail.status === 'fulfilled'
          ? mail.value
          : { status: 'unavailable' as const },
      providers: {
        gemini: {
          configured: Boolean(
            this.config.get<string>('GEMINI_API_KEY')?.trim(),
          ),
          stylistModel: this.config.getOrThrow<string>('GEMINI_STYLIST_MODEL'),
          tryOnModel: this.config.getOrThrow<string>('GEMINI_TRYON_MODEL'),
        },
        vnpay: {
          configured: this.config.get('VNPAY_ENABLED') === 'true',
          sandbox: true,
        },
        momo: {
          configured: this.config.get('MOMO_ENABLED') === 'true',
          sandbox: true,
        },
        zalopay: {
          configured: this.config.get('ZALOPAY_ENABLED') === 'true',
          sandbox: true,
        },
        shipping: { mode: 'local', sandbox: true },
      },
    };
  }
}
export type OperationsSnapshot = Awaited<
  ReturnType<OperationsService['snapshot']>
>;
