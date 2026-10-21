import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Admin, CurrentUser, Identity } from '../../common/decorators/auth';
import { RefundsService } from './refunds.service';
import { CreateRefundDto, QueryRefundDto } from './refunds.dto';
@ApiBearerAuth()
@ApiTags('refunds')
@Controller('orders/:id/refunds')
export class RefundsController {
  constructor(private readonly service: RefundsService) {}
  @Get() state(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.state(id, u.id);
  }
}
@Admin()
@ApiBearerAuth()
@ApiTags('refunds')
@Controller('admin/orders/:id/refunds')
export class AdminRefundsController {
  constructor(private readonly service: RefundsService) {}
  @Get() state(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.state(id);
  }
  @Post() create(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CreateRefundDto,
  ) {
    return this.service.create(u.id, id, dto);
  }
  @Post(':refundId/query') query(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('refundId', ParseUUIDPipe) refundId: string,
    @Body() dto: QueryRefundDto,
  ) {
    return this.service.query(u.id, id, refundId, dto);
  }
}
