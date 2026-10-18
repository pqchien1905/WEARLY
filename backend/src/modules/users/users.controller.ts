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
import { UsersService } from './users.service';
import { AddressDto, ProfileDto, UpdateAddressDto } from './dto/user.dto';
@ApiTags('users')
@ApiBearerAuth()
@Controller('users/me')
export class UsersController {
  constructor(private readonly service: UsersService) {}
  @Get() me(@CurrentUser() u: Identity) {
    return this.service.me(u.id);
  }
  @Patch() update(@CurrentUser() u: Identity, @Body() dto: ProfileDto) {
    return this.service.update(u.id, dto);
  }
  @Get('addresses') addresses(@CurrentUser() u: Identity) {
    return this.service.addresses(u.id);
  }
  @Post('addresses') create(
    @CurrentUser() u: Identity,
    @Body() dto: AddressDto,
  ) {
    return this.service.saveAddress(u.id, dto);
  }
  @Patch('addresses/:id') patch(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateAddressDto,
  ) {
    return this.service.saveAddress(u.id, dto, id);
  }
  @Delete('addresses/:id') delete(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.deleteAddress(u.id, id);
  }
}
