import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { VnpayProvider } from '../../integrations/payments/vnpay.provider';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
@Module({
  controllers: [PaymentsController],
  providers: [
    { provide: 'VNPAY_HTTP', useValue: fetch },
    {
      provide: VnpayProvider,
      inject: [ConfigService, 'VNPAY_HTTP'],
      useFactory: (config: ConfigService, http: typeof fetch) =>
        new VnpayProvider(config, http),
    },
    PaymentsService,
  ],
  exports: [VnpayProvider],
})
export class PaymentsModule {}
