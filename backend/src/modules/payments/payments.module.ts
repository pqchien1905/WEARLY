import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { VnpayProvider } from '../../integrations/payments/vnpay.provider';
import { MomoProvider } from '../../integrations/payments/momo.provider';
import { ZalopayProvider } from '../../integrations/payments/zalopay.provider';
import { WALLET_HTTP } from '../../integrations/payments/wallet-gateway';
import { WalletGateways } from '../../integrations/payments/wallet-gateways';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
@Module({
  controllers: [PaymentsController],
  providers: [
    { provide: 'VNPAY_HTTP', useValue: fetch },
    { provide: WALLET_HTTP, useValue: fetch },
    {
      provide: VnpayProvider,
      inject: [ConfigService, 'VNPAY_HTTP'],
      useFactory: (config: ConfigService, http: typeof fetch) =>
        new VnpayProvider(config, http),
    },
    {
      provide: MomoProvider,
      inject: [ConfigService, WALLET_HTTP],
      useFactory: (config: ConfigService, http: typeof fetch) =>
        new MomoProvider(config, http),
    },
    {
      provide: ZalopayProvider,
      inject: [ConfigService, WALLET_HTTP],
      useFactory: (config: ConfigService, http: typeof fetch) =>
        new ZalopayProvider(config, http),
    },
    WalletGateways,
    PaymentsService,
  ],
  exports: [VnpayProvider, WalletGateways],
})
export class PaymentsModule {}
