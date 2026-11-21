import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiHeader, ApiTags } from '@nestjs/swagger';
import { CurrentUser, Identity } from '../../common/decorators/auth';
import { OrdersService } from './orders.service';
import { ChangeOrderAddressDto, CreateOrderDto } from './dto/order.dto';
import { PageDto } from '../products/dto/query-products.dto';
@ApiTags('orders')
@ApiBearerAuth()
@Controller('orders')
export class OrdersController {
  constructor(private readonly service: OrdersService) {}
  @ApiHeader({ name: 'Idempotency-Key', required: true }) @Post() create(
    @CurrentUser() u: Identity,
    @Headers('idempotency-key') key: string | undefined,
    @Body() dto: CreateOrderDto,
  ) {
    return this.service.create(u.id, key, dto);
  }
  @Get() list(@CurrentUser() u: Identity, @Query() q: PageDto) {
    return this.service.list(u.id, q);
  }
  @Get(':id') get(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.get(u.id, id);
  }
  @Patch(':id/address') changeAddress(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ChangeOrderAddressDto,
  ) {
    return this.service.changeAddress(u.id, id, dto.addressId);
  }
  @Post(':id/cancel') cancel(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.cancel(u.id, id);
  }
}
