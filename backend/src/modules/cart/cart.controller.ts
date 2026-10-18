import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser, Identity } from '../../common/decorators/auth';
import { CartService } from './cart.service';
import { AddCartItemDto, QuantityDto } from './dto/cart.dto';
@ApiTags('cart')
@ApiBearerAuth()
@Controller('cart')
export class CartController {
  constructor(private readonly service: CartService) {}
  @Get() get(@CurrentUser() u: Identity) {
    return this.service.get(u.id);
  }
  @Post('items') add(@CurrentUser() u: Identity, @Body() dto: AddCartItemDto) {
    return this.service.mutate(u.id, 'add', dto);
  }
  @Patch('items/:id') patch(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: QuantityDto,
  ) {
    return this.service.mutate(u.id, 'update', { ...dto, id });
  }
  @Delete('items/:id') delete(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.mutate(u.id, 'delete', { id });
  }
}
