import { Module } from '@nestjs/common';
import { ProductsController } from './products.controller';
import { ProductsService } from './products.service';
import { CollectionsService } from './collections.service';
import {
  CollectionsController,
  AdminCollectionsController,
} from './collections.controller';
@Module({
  controllers: [
    ProductsController,
    CollectionsController,
    AdminCollectionsController,
  ],
  providers: [ProductsService, CollectionsService],
  exports: [ProductsService],
})
export class ProductsModule {}
