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
import { ReturnsService } from './returns.service';
import {
  AdminCancelDto,
  CreateReturnDto,
  DecideReturnDto,
  QuoteReturnDto,
  ReceiveReturnDto,
} from './returns.dto';
@ApiBearerAuth()
@ApiTags('returns')
@Controller('orders/:id/returns')
export class ReturnsController {
  constructor(private readonly service: ReturnsService) {}
  @Get() state(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.state(u.id, id);
  }
  @Post('quote') preview(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: QuoteReturnDto,
  ) {
    return this.service.preview(u.id, id, dto);
  }
  @Post() create(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CreateReturnDto,
  ) {
    return this.service.create(u.id, id, dto);
  }
}
@Admin()
@ApiBearerAuth()
@ApiTags('returns')
@Controller('admin/orders/:id')
export class AdminReturnsController {
  constructor(private readonly service: ReturnsService) {}
  @Post('cancel') cancel(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdminCancelDto,
  ) {
    return this.service.cancel(u.id, id, dto);
  }
  @Post('returns/:returnId/decision') decide(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('returnId', ParseUUIDPipe) returnId: string,
    @Body() dto: DecideReturnDto,
  ) {
    return this.service.decide(u.id, id, returnId, dto);
  }
  @Post('returns/:returnId/receive') receive(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('returnId', ParseUUIDPipe) returnId: string,
    @Body() dto: ReceiveReturnDto,
  ) {
    return this.service.receive(u.id, id, returnId, dto);
  }
}
