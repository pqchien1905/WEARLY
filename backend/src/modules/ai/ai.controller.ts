import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Headers,
  Header,
  StreamableFile,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser, Identity } from '../../common/decorators/auth';
import { AiService } from './ai.service';
import { TryOnDto } from './dto/try-on.dto';
@ApiTags('ai')
@ApiBearerAuth()
@Controller('ai/try-on')
export class AiController {
  constructor(private readonly service: AiService) {}
  @Header('Cache-Control', 'private, no-store')
  @Get('status')
  status(@CurrentUser() u: Identity) {
    return this.service.status(u.id);
  }
  @Header('Cache-Control', 'private, no-store')
  @Post('jobs')
  create(
    @CurrentUser() u: Identity,
    @Headers('idempotency-key') key: string | undefined,
    @Body() dto: TryOnDto,
  ) {
    return this.service.create(u.id, key, dto);
  }
  @Header('Cache-Control', 'private, no-store')
  @Get('jobs')
  list(@CurrentUser() u: Identity) {
    return this.service.list(u.id);
  }
  @Header('Cache-Control', 'private, no-store')
  @Get('jobs/:id/result')
  async result(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    const value = await this.service.result(u.id, id);
    return new StreamableFile(value.bytes, {
      type: value.contentType,
      disposition: 'inline',
    });
  }
  @Header('Cache-Control', 'private, no-store')
  @Get('jobs/:id')
  get(@CurrentUser() u: Identity, @Param('id', ParseUUIDPipe) id: string) {
    return this.service.get(u.id, id);
  }
}
