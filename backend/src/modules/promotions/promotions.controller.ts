import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { Admin, CurrentUser, Identity } from '../../common/decorators/auth';
import { PageDto } from '../products/dto/query-products.dto';
import { PromotionsService } from './promotions.service';
import {
  CreatePromotionDto,
  UpdatePromotionDto,
  PreviewPromotionDto,
} from './promotions.dto';
@Controller('promotions')
export class PromotionsController {
  constructor(private readonly service: PromotionsService) {}
  @Post('preview') preview(
    @CurrentUser() u: Identity,
    @Body() dto: PreviewPromotionDto,
  ) {
    return this.service.preview(u.id, dto);
  }
}
@Admin('promotions.manage')
@Controller('admin/promotions')
export class AdminPromotionsController {
  constructor(private readonly service: PromotionsService) {}
  @Get() list(@Query() q: PageDto) {
    return this.service.list(q);
  }
  @Get(':id') get(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.get(id);
  }
  @Post() create(@CurrentUser() u: Identity, @Body() dto: CreatePromotionDto) {
    return this.service.create(u.id, dto);
  }
  @Patch(':id') update(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdatePromotionDto,
  ) {
    return this.service.update(u.id, id, dto);
  }
}
