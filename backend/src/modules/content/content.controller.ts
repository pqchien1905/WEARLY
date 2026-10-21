import { Body, Controller, Get, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  Admin,
  CurrentUser,
  Identity,
  Public,
} from '../../common/decorators/auth';
import { ContentService } from './content.service';
import { ContentVersionDto, SaveContentDto } from './content.dto';

@ApiTags('content')
@Controller('content')
export class ContentController {
  constructor(private readonly service: ContentService) {}
  @Public() @Get() read() {
    return this.service.readPublished();
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
