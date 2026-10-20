import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ImageLifecycleService } from '../modules/uploads/image-lifecycle.service';
import { CatalogMediaService } from '../modules/catalog-media/catalog-media.service';
@Injectable()
export class RetentionWorker implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private active?: Promise<void>;
  private readonly logger = new Logger('ImageRetention');
  constructor(
    private readonly lifecycle: ImageLifecycleService,
    private readonly catalog: CatalogMediaService,
  ) {}
  onModuleInit() {
    this.timer = setInterval(() => {
      if (this.active) return;
      this.active = Promise.allSettled([
        this.lifecycle.purgeExpired(),
        this.catalog.purgeExpired(),
      ])
        .then((results) => {
          if (results.some((result) => result.status === 'rejected'))
            throw new Error('RETENTION_RETRY_PENDING');
        })
        .catch(() => {
          this.logger.warn('IMAGE_RETENTION_RETRY_PENDING');
        })
        .finally(() => {
          this.active = undefined;
        });
    }, 60000);
  }
  async onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
    await this.active;
  }
}
