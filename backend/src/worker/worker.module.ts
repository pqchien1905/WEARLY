import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validateEnv } from '../config/env.validation';
import { PrismaModule } from '../database/prisma.module';
import { AiProcessor } from './ai.processor';
import {
  DisabledTryOnProvider,
  TryOnProvider,
} from '../integrations/ai-providers/try-on.provider';
import { StorageModule } from '../integrations/storage/storage.module';
import { ImageLifecycleService } from '../modules/uploads/image-lifecycle.service';
import { RetentionWorker } from './retention.worker';
import { RecoveryModule } from '../modules/recovery/recovery.module';
import { RecoveryWorker } from './recovery.worker';
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    PrismaModule,
    StorageModule,
    RecoveryModule,
  ],
  providers: [
    AiProcessor,
    ImageLifecycleService,
    RetentionWorker,
    RecoveryWorker,
    { provide: TryOnProvider, useClass: DisabledTryOnProvider },
  ],
})
export class WorkerModule {}
