import { Module } from '@nestjs/common';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';
import { PaymentsModule } from '../payments/payments.module';
import { PromotionsModule } from '../promotions/promotions.module';
import { ReturnsModule } from '../returns/returns.module';
@Module({
  imports: [PaymentsModule, PromotionsModule, ReturnsModule],
  controllers: [OrdersController],
  providers: [OrdersService],
})
export class OrdersModule {}
