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
import { CatalogMediaModule } from '../modules/catalog-media/catalog-media.module';
import { MailModule } from '../modules/mail/mail.module';
import { MailWorker } from './mail.worker';
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    PrismaModule,
    StorageModule,
    RecoveryModule,
    CatalogMediaModule,
    MailModule,
  ],
  providers: [
    AiProcessor,
    ImageLifecycleService,
    RetentionWorker,
    RecoveryWorker,
    MailWorker,
    { provide: TryOnProvider, useClass: DisabledTryOnProvider },
  ],
})
export class WorkerModule {}
