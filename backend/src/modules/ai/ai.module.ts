import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { TryOnProvider } from '../../integrations/ai-providers/try-on.provider';
import { GeminiTryOnProvider } from '../../integrations/ai-providers/gemini-tryon.provider';
import { GarmentReader } from '../../integrations/ai-providers/garment-reader.service';
import { StorageModule } from '../../integrations/storage/storage.module';
import {
  GeminiClient,
  GEMINI_HTTP,
} from '../../integrations/ai-providers/gemini.client';
import { AiUsageService } from './ai-usage.service';
import { StylistService } from './stylist.service';
import { StylistController } from './stylist.controller';
@Module({
  imports: [StorageModule],
  controllers: [AiController, StylistController],
  providers: [
    AiService,
    GeminiClient,
    AiUsageService,
    StylistService,
    GarmentReader,
    {
      provide: GEMINI_HTTP,
      useValue: (...args: Parameters<typeof fetch>) => fetch(...args),
    },
    { provide: TryOnProvider, useClass: GeminiTryOnProvider },
  ],
})
export class AiModule {}
