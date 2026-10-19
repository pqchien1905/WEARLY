import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
} from '@nestjs/common';
import { ApiBearerAuth, ApiHeader, ApiTags } from '@nestjs/swagger';
import { CurrentUser, Identity } from '../../common/decorators/auth';
import { UsersService } from './users.service';
import { AddressDto, ProfileDto, UpdateAddressDto } from './dto/user.dto';
import { SaveStyleDto } from './dto/style.dto';
import { StyleService } from './style.service';
@ApiTags('users')
@ApiBearerAuth()
@Controller('users/me')
export class UsersController {
  constructor(
    private readonly service: UsersService,
    private readonly styles: StyleService,
  ) {}
  @Get('style') style(@CurrentUser() u: Identity) {
    return this.styles.get(u.id);
  }
  @Put('style') saveStyle(
    @CurrentUser() u: Identity,
    @Body() dto: SaveStyleDto,
  ) {
    return this.styles.save(u.id, dto);
  }
  @Get() me(@CurrentUser() u: Identity) {
    return this.service.me(u.id);
  }
  @Patch() update(@CurrentUser() u: Identity, @Body() dto: ProfileDto) {
    return this.service.update(u.id, dto);
  }
  @Get('addresses') addresses(@CurrentUser() u: Identity) {
    return this.service.addresses(u.id);
  }
  @ApiHeader({
    name: 'Idempotency-Key',
    required: false,
    description:
      '16–128 ASCII letters, digits, underscore or hyphen; reuse for the same create attempt.',
  })
  @Post('addresses')
  create(
    @CurrentUser() u: Identity,
    @Body() dto: AddressDto,
    @Headers('idempotency-key') key: string | undefined,
  ) {
    return this.service.saveAddress(u.id, dto, undefined, key);
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
