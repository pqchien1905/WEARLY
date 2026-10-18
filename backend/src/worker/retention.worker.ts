import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ImageLifecycleService } from '../modules/uploads/image-lifecycle.service';
@Injectable()
export class RetentionWorker implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private active?: Promise<void>;
  private readonly logger = new Logger('ImageRetention');
  constructor(private readonly lifecycle: ImageLifecycleService) {}
  onModuleInit() {
    this.timer = setInterval(() => {
      if (this.active) return;
      this.active = this.lifecycle
        .purgeExpired()
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
