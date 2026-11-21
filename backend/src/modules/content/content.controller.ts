import { Body, Controller, Get, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  Admin,
  CurrentUser,
  Identity,
  Public,
} from '../../common/decorators/auth';
import { AdminPageDto as PageDto } from '../../common/admin-page.dto';
import { ContentService } from './content.service';
import {
  ContentVersionDto,
  SaveContentDto,
  NewsletterDto,
} from './content.dto';
import { Throttle } from '@nestjs/throttler';

@ApiTags('content')
@Controller('content')
export class ContentController {
  constructor(private readonly service: ContentService) {}
  @Public() @Get() read() {
    return this.service.readPublished();
  }
  @Public()
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @Post('newsletter')
  subscribe(@Body() dto: NewsletterDto) {
    return this.service.subscribe(dto.email);
  }
}

@Admin('content.manage')
@ApiBearerAuth()
@ApiTags('admin')
@Controller('admin/content')
export class AdminContentController {
  constructor(private readonly service: ContentService) {}
  @Get() read() {
    return this.service.readDraft();
  }
  @Get('history') history(@Query() q: PageDto) {
    return this.service.history(q);
  }
  @Post('restore') restore(
    @CurrentUser() u: Identity,
    @Body() dto: ContentVersionDto,
  ) {
    return this.service.restore(u.id, dto);
  }
  @Put() save(@CurrentUser() u: Identity, @Body() dto: SaveContentDto) {
    return this.service.save(u.id, dto);
  }
  @Post('publish') publish(
    @CurrentUser() u: Identity,
    @Body() dto: ContentVersionDto,
  ) {
    return this.service.publish(u.id, dto);
  }
}
