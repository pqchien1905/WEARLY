import { Injectable } from '@nestjs/common';
import { MomoProvider } from './momo.provider';
import { ZalopayProvider } from './zalopay.provider';
import {
  WalletGateway,
  WalletProvider,
  walletProviders,
} from './wallet-gateway';

/** Lookup for the e-wallet gateways by their persisted payment provider name. */
@Injectable()
export class WalletGateways {
  private readonly byName: Record<WalletProvider, WalletGateway>;
  constructor(momo: MomoProvider, zalopay: ZalopayProvider) {
    this.byName = { momo, zalopay };
  }
  get(provider: string | null | undefined): WalletGateway | undefined {
    return (walletProviders as readonly string[]).includes(provider ?? '')
      ? this.byName[provider as WalletProvider]
      : undefined;
  }
  enabled(provider: WalletProvider) {
    return this.byName[provider].enabled;
  }
}
