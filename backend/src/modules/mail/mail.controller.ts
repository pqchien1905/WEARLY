import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
} from '@nestjs/common';
import { IsIn, IsISO8601 } from 'class-validator';
import { AdminPageDto } from '../../common/admin-page.dto';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Admin, CurrentUser, Identity } from '../../common/decorators/auth';
import { MailService } from './mail.service';
class MailActionDto {
  @IsIn(['hold', 'release', 'cancel']) action!: 'hold' | 'release' | 'cancel';
  @IsISO8601() expectedUpdatedAt!: string;
}
@Admin('mail.read')
@ApiBearerAuth()
@ApiTags('mail')
@Controller('admin/mail')
export class MailController {
  constructor(private readonly mail: MailService) {}
  @Get() overview(@Query() query: AdminPageDto) {
    return this.mail.overview(query);
  }
  @Get(':id') preview(@Param('id', ParseUUIDPipe) id: string) {
    return this.mail.preview(id);
  }
  @Admin('mail.manage')
  @Post(':id')
  manage(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: MailActionDto,
  ) {
    return this.mail.manage(user.id, id, dto.action, dto.expectedUpdatedAt);
  }
}
