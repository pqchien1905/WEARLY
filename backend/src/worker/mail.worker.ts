import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { MailService } from '../modules/mail/mail.service';
@Injectable()
export class MailWorker implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private active?: Promise<void>;
  private readonly logger = new Logger(MailWorker.name);
  constructor(private readonly mail: MailService) {}
  onModuleInit() {
    if (!this.mail.enabled()) return;
    const tick = () => {
      if (this.active) return;
      this.active = this.mail
        .processBatch()
        .catch(() => {
          this.logger.warn('MAIL_WORKER_RETRY_PENDING');
        })
        .finally(() => {
          this.active = undefined;
        });
    };
    tick();
    this.timer = setInterval(tick, 5000);
    this.timer.unref();
  }
  async onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
    this.mail.stop();
    await this.active;
  }
}
