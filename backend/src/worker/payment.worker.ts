import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { PaymentsService } from '../modules/payments/payments.service';
import { ConfigService } from '@nestjs/config';
@Injectable()
export class PaymentWorker implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private active?: Promise<void>;
  private readonly logger = new Logger(PaymentWorker.name);
  constructor(
    private readonly payments: PaymentsService,
    private readonly config: ConfigService,
  ) {}
  onModuleInit() {
    if (this.config.get('NODE_ENV') === 'test') return;
    const tick = () => {
      if (this.active) return;
      this.active = this.payments
        .expireUnpaid()
        .catch(() => {
          this.logger.warn('PAYMENT_EXPIRY_RETRY');
        })
        .finally(() => {
          this.active = undefined;
        });
    };
    this.timer = setInterval(tick, 60000);
    this.timer.unref();
  }
  async onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
    await this.active;
  }
}
