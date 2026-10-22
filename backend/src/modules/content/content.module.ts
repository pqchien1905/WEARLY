import { Module } from '@nestjs/common';
import {
  AdminContentController,
  ContentController,
} from './content.controller';
import { ContentService } from './content.service';
import { StorefrontController } from './storefront.controller';
import { StorefrontService } from './storefront.service';
import { ProductsModule } from '../products/products.module';

@Module({
  imports: [ProductsModule],
  controllers: [
    ContentController,
    AdminContentController,
    StorefrontController,
  ],
  providers: [ContentService, StorefrontService],
})
export class ContentModule {}
