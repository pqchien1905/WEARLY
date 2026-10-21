import { Controller, Get } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Admin } from '../../common/decorators/auth';
import { MailService } from './mail.service';
@Admin('mail.read')
@ApiBearerAuth()
@ApiTags('mail')
@Controller('admin/mail')
export class MailController {
  constructor(private readonly mail: MailService) {}
  @Get() overview() {
    return this.mail.overview();
  }
}
