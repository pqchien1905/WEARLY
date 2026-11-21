import { Module } from '@nestjs/common';
import {
  SupportController,
  AdminSupportController,
  CustomerSupportController,
} from './support.controller';
import { SupportService } from './support.service';
@Module({
  controllers: [
    SupportController,
    AdminSupportController,
    CustomerSupportController,
  ],
  providers: [SupportService],
})
export class SupportModule {}
