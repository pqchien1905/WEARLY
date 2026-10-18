import { Controller, Delete, Get, Param, ParseUUIDPipe, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser, Identity } from '../../common/decorators/auth';
import { WishlistService } from './wishlist.service';
@ApiTags('wishlist')
@ApiBearerAuth()
@Controller('wishlist')
export class WishlistController {
  constructor(private readonly service: WishlistService) {}
  @Get() get(@CurrentUser() user: Identity) { return this.service.get(user.id); }
  @Put(':productId') save(@CurrentUser() user: Identity, @Param('productId', ParseUUIDPipe) productId: string) {
    return this.service.set(user.id, productId, true);
  }
  @Delete(':productId') remove(@CurrentUser() user: Identity, @Param('productId', ParseUUIDPipe) productId: string) {
    return this.service.set(user.id, productId, false);
  }
}
