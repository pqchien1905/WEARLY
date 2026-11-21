import { GeoModule } from './modules/geo/geo.module';
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { validateEnv } from './config/env.validation';
import { PrismaModule } from './database/prisma.module';
import { AuthGuard } from './common/guards/auth.guard';
import { AuthModule } from './modules/auth/auth.module';
import { UsersModule } from './modules/users/users.module';
import { ProductsModule } from './modules/products/products.module';
import { CartModule } from './modules/cart/cart.module';
import { OrdersModule } from './modules/orders/orders.module';
import { AdminModule } from './modules/admin/admin.module';
import { HealthModule } from './modules/health/health.module';
import { AiModule } from './modules/ai/ai.module';
import { UploadsModule } from './modules/uploads/uploads.module';
import { WishlistModule } from './modules/wishlist/wishlist.module';
import { ReviewsModule } from './modules/reviews/reviews.module';
import { ContentModule } from './modules/content/content.module';
import { CatalogMediaModule } from './modules/catalog-media/catalog-media.module';
import { SupportModule } from './modules/support/support.module';
import { MailModule } from './modules/mail/mail.module';
import { OperationsModule } from './modules/operations/operations.module';
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    PrismaModule,
    JwtModule.register({ global: true }),
    ThrottlerModule.forRoot([{ ttl: 60000, limit: 300 }]),
    AuthModule,
    UsersModule,
    ProductsModule,
    CartModule,
    OrdersModule,
    AdminModule,
    HealthModule,
    AiModule,
    UploadsModule,
    WishlistModule,
    ReviewsModule,
    ContentModule,
    CatalogMediaModule,
    SupportModule,
    MailModule,
    OperationsModule,
    GeoModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
  ],
})
export class AppModule {}
