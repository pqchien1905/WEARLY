import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
} from '@nestjs/common';
import {
  IsInt,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { Throttle } from '@nestjs/throttler';
import {
  Admin,
  CurrentUser,
  Identity,
  Public,
} from '../../common/decorators/auth';
import { AdminPageDto } from '../../common/admin-page.dto';
import { NewsletterService } from './newsletter.service';
class UnsubscribeDto {
  @IsUUID() token!: string;
}
class CampaignDto {
  @IsUUID() requestKey!: string;
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  subject!: string;
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(1)
  @MaxLength(10000)
  body!: string;
}
class QueueDto {
  @IsInt() @Min(0) expectedVersion!: number;
}
@Controller('content/newsletter')
export class NewsletterController {
  constructor(private readonly service: NewsletterService) {}
  @Public()
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @Post('unsubscribe')
  unsubscribe(@Body() dto: UnsubscribeDto) {
    return this.service.unsubscribe(dto.token);
  }
}
@Admin('content.manage')
@Controller('admin/newsletter')
export class AdminNewsletterController {
  constructor(private readonly service: NewsletterService) {}
  @Get() list(@Query() q: AdminPageDto) {
    return this.service.subscriptions(q.page, q.limit);
  }
  @Post('subscriptions/:id/unsubscribe') remove(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.remove(u.id, id);
  }
  @Get('campaigns') campaigns() {
    return this.service.campaigns();
  }
  @Post('campaigns') save(
    @CurrentUser() u: Identity,
    @Body() dto: CampaignDto,
  ) {
    return this.service.save(u.id, dto);
  }
  @Post('campaigns/:id/queue') queue(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: QueueDto,
  ) {
    return this.service.queue(u.id, id, dto.expectedVersion);
  }
}
