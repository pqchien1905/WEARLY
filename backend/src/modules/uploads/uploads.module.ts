import { Module } from '@nestjs/common';
import { StorageModule } from '../../integrations/storage/storage.module';
import { UploadsController } from './uploads.controller';
import { UploadsService } from './uploads.service';
import { ImageLifecycleService } from './image-lifecycle.service';
@Module({
  imports: [StorageModule],
  controllers: [UploadsController],
  providers: [UploadsService, ImageLifecycleService],
  exports: [ImageLifecycleService],
})
export class UploadsModule {}
