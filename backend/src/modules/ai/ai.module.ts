import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import {
  DisabledTryOnProvider,
  TryOnProvider,
} from '../../integrations/ai-providers/try-on.provider';
import { StorageModule } from '../../integrations/storage/storage.module';
@Module({
  imports: [StorageModule],
  controllers: [AiController],
  providers: [
    AiService,
    { provide: TryOnProvider, useClass: DisabledTryOnProvider },
  ],
})
export class AiModule {}
