import {
  Body,
  Controller,
  Get,
  Headers,
  Header,
  Param,
  ParseUUIDPipe,
  Post,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser, Identity } from '../../common/decorators/auth';
import { StylistDto } from './dto/stylist.dto';
import { StylistService } from './stylist.service';
@ApiTags('ai')
@ApiBearerAuth()
@Controller('ai')
export class StylistController {
  constructor(private readonly service: StylistService) {}
  @Header('Cache-Control', 'private, no-store')
  @Get('status')
  status(@CurrentUser() u: Identity) {
    return this.service.status(u.id);
  }
  @Header('Cache-Control', 'private, no-store')
  @Post('stylist/requests')
  create(
    @CurrentUser() u: Identity,
    @Headers('idempotency-key') key: string | undefined,
    @Body() dto: StylistDto,
  ) {
    return this.service.create(u.id, key, dto);
  }
  @Header('Cache-Control', 'private, no-store')
  @Get('stylist/requests/latest')
  latest(@CurrentUser() u: Identity) {
    return this.service.latest(u.id);
  }
  @Header('Cache-Control', 'private, no-store')
  @Get('stylist/requests/:key')
  get(
    @CurrentUser() u: Identity,
    @Param('key', new ParseUUIDPipe({ version: '4' })) key: string,
  ) {
    return this.service.get(u.id, key);
  }
}
