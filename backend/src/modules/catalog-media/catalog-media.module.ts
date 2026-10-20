import { Module } from '@nestjs/common';
import { StorageModule } from '../../integrations/storage/storage.module';
import { CatalogMediaController } from './catalog-media.controller';
import { CatalogMediaService } from './catalog-media.service';
@Module({
  imports: [StorageModule],
  controllers: [CatalogMediaController],
  providers: [CatalogMediaService],
  exports: [CatalogMediaService],
})
export class CatalogMediaModule {}
