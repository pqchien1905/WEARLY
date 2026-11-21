import { Module } from '@nestjs/common';
import {
  AdminContentController,
  ContentController,
} from './content.controller';
import { ContentService } from './content.service';
import { StorefrontController } from './storefront.controller';
import { StorefrontService } from './storefront.service';
import { ProductsModule } from '../products/products.module';
import { NewsletterService } from './newsletter.service';
import {
  NewsletterController,
  AdminNewsletterController,
} from './newsletter.controller';

@Module({
  imports: [ProductsModule],
  controllers: [
    ContentController,
    AdminContentController,
    StorefrontController,
    NewsletterController,
    AdminNewsletterController,
  ],
  providers: [ContentService, StorefrontService, NewsletterService],
})
export class ContentModule {}
