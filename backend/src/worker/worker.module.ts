import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validateEnv } from '../config/env.validation';
import { PrismaModule } from '../database/prisma.module';
import { AiProcessor } from './ai.processor';
import {
  DisabledTryOnProvider,
  TryOnProvider,
} from '../integrations/ai-providers/try-on.provider';
import { StorageService } from '../integrations/storage/storage.service';
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    PrismaModule,
  ],
  providers: [
    AiProcessor,
    StorageService,
    { provide: TryOnProvider, useClass: DisabledTryOnProvider },
  ],
})
export class WorkerModule {}
