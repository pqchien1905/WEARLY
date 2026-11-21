import { Controller, Get, Query } from '@nestjs/common';
import { AdminPageDto } from '../../common/admin-page.dto';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Admin } from '../../common/decorators/auth';
import { MailService } from './mail.service';
@Admin('mail.read')
@ApiBearerAuth()
@ApiTags('mail')
@Controller('admin/mail')
export class MailController {
  constructor(private readonly mail: MailService) {}
  @Get() overview(@Query() query: AdminPageDto) {
    return this.mail.overview(query);
  }
}
