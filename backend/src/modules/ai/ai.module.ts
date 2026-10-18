import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import {
  DisabledTryOnProvider,
  TryOnProvider,
} from '../../integrations/ai-providers/try-on.provider';
import { StorageService } from '../../integrations/storage/storage.service';
@Module({
  controllers: [AiController],
  providers: [
    AiService,
    StorageService,
    { provide: TryOnProvider, useClass: DisabledTryOnProvider },
  ],
})
export class AiModule {}
