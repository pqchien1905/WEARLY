import { Injectable } from '@nestjs/common';
export type TryOnInput = {
  jobId: string;
  // Legacy worker input is removed when durable private jobs are connected.
  imageUrl?: string;
  image?: { bytes: Uint8Array; contentType: 'image/jpeg' | 'image/png' };
  garment?: { bytes: Uint8Array; contentType: 'image/jpeg' | 'image/png' };
  sku: string;
  signal: AbortSignal;
};
export type TryOnOutput = {
  bytes: Uint8Array;
  contentType: 'image/jpeg' | 'image/png';
  inputTokens?: number | null;
  outputTokens?: number | null;
};
export abstract class TryOnProvider {
  abstract readonly enabled: boolean;
  abstract generate(input: TryOnInput): Promise<TryOnOutput>;
}
@Injectable()
export class DisabledTryOnProvider extends TryOnProvider {
  readonly enabled = false;
  async generate(_input: TryOnInput): Promise<TryOnOutput> {
    throw new Error('AI_PROVIDER_NOT_CONFIGURED');
  }
}
