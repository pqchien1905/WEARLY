import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser, Identity } from '../../common/decorators/auth';
import { AiService } from './ai.service';
import { TryOnDto } from './dto/try-on.dto';
@ApiTags('ai')
@ApiBearerAuth()
@Controller('ai/try-on/jobs')
export class AiController {
  constructor(private readonly service: AiService) {}
  @Post() create(@CurrentUser() u: Identity, @Body() dto: TryOnDto) {
    return this.service.create(u.id, dto);
  }
  @Get(':id') get(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.get(u.id, id);
  }
}
