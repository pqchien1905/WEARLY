import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
} from '@nestjs/common';
import { IsOptional, IsUUID } from 'class-validator';
import { Admin, CurrentUser, Identity } from '../../common/decorators/auth';
import { PaymentsService } from './payments.service';
class ReconcileDto {
  @IsOptional() @IsUUID() attemptId?: string;
}
@Controller('admin/payments')
@Admin('payments.manage')
export class AdminPaymentsController {
  constructor(private readonly service: PaymentsService) {}
  @Get('overdue') overdue() {
    return this.service.overdue();
  }
  @Post('orders/:id/reconcile') reconcile(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReconcileDto,
  ) {
    return this.service.reconcile(undefined, id, user.id, dto.attemptId);
  }
}
