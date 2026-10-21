import { Module } from '@nestjs/common';
import {
  ReturnsController,
  AdminReturnsController,
} from './returns.controller';
import { ReturnsService } from './returns.service';
@Module({
  controllers: [ReturnsController, AdminReturnsController],
  providers: [ReturnsService],
})
export class ReturnsModule {}
