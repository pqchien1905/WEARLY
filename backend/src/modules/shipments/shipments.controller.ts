import { Body, Controller, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Admin, CurrentUser, Identity } from '../../common/decorators/auth';
import { ShipmentEventDto } from './shipments.dto';
import { ShipmentsService } from './shipments.service';
@Admin('orders.fulfill')
@ApiBearerAuth()
@ApiTags('shipments')
@Controller('admin/orders')
export class ShipmentsController {
  constructor(private readonly service: ShipmentsService) {}
  @Post(':id/shipment-events') event(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ShipmentEventDto,
  ) {
    return this.service.event(u.id, id, dto);
  }
}
