import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import {
  Admin,
  CurrentUser,
  Identity,
  Public,
} from '../../common/decorators/auth';
import {
  CreateSupportDto,
  CustomerFollowUpDto,
  CustomerSupportDto,
  CustomerSupportPageDto,
  ListSupportDto,
  ReplySupportDto,
  StatusSupportDto,
} from './support.dto';
import { SupportService } from './support.service';
@ApiTags('support')
@Controller('support')
export class SupportController {
  constructor(private readonly service: SupportService) {}
  @Public()
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post()
  create(@Body() dto: CreateSupportDto) {
    return this.service.create(dto);
  }
}
@Admin('support.manage')
@ApiBearerAuth()
@ApiTags('support')
@Controller('admin/support')
export class AdminSupportController {
  constructor(private readonly service: SupportService) {}
  @Get() list(@Query() dto: ListSupportDto) {
    return this.service.list(dto);
  }
  @Get(':id') detail(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.detail(id);
  }
  @Post(':id/replies') reply(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReplySupportDto,
  ) {
    return this.service.reply(user.id, id, dto);
  }
  @Patch(':id') status(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: StatusSupportDto,
  ) {
    return this.service.status(user.id, id, dto);
  }
}
@ApiTags('support')
@ApiBearerAuth()
@Controller('users/me/support')
export class CustomerSupportController {
  constructor(private readonly service: SupportService) {}
  @Get() list(
    @CurrentUser() user: Identity,
    @Query() q: CustomerSupportPageDto,
  ) {
    return this.service.mine(user.id, q);
  }
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post()
  create(@CurrentUser() user: Identity, @Body() dto: CustomerSupportDto) {
    return this.service.createForCustomer(user.id, dto);
  }
  @Get(':id') detail(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.mineDetail(user.id, id);
  }
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @Post(':id/replies')
  followUp(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CustomerFollowUpDto,
  ) {
    return this.service.followUp(user.id, id, dto);
  }
}
