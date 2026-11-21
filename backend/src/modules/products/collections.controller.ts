import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  Admin,
  CurrentUser,
  Identity,
  Public,
} from '../../common/decorators/auth';
import { PageDto, QueryProductsDto } from './dto/query-products.dto';
import { CreateCollectionDto, UpdateCollectionDto } from './collections.dto';
import { DeleteCollectionDto } from './collections.dto';
import {
  AdminCollectionsQueryDto,
  CollectionCoverQueryDto,
} from '../admin/dto/admin-collections-query.dto';
import { CollectionsService } from './collections.service';
@Public()
@ApiTags('collections')
@Controller('collections')
export class CollectionsController {
  constructor(private readonly service: CollectionsService) {}
  @Get() list(@Query() q: PageDto) {
    return this.service.list(q);
  }
  @Get(':slug') detail(
    @Param('slug') slug: string,
    @Query() q: QueryProductsDto,
  ) {
    return this.service.detail(slug, q);
  }
}
@Admin('content.manage')
@ApiBearerAuth()
@ApiTags('admin')
@Controller('admin/collections')
export class AdminCollectionsController {
  constructor(private readonly service: CollectionsService) {}
  @Get() list(@Query() q: AdminCollectionsQueryDto) {
    return this.service.adminList(q);
  }
  @Get('summary') summary() {
    return this.service.adminSummary();
  }
  @Get('styles') styles() {
    return this.service.styles();
  }
  @Get('covers') covers(@Query() q: CollectionCoverQueryDto) {
    return this.service.covers(q);
  }
  @Get(':id') detail(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.adminDetail(id);
  }
  @Delete(':id') remove(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DeleteCollectionDto,
  ) {
    return this.service.remove(user.id, id, dto.expectedVersion);
  }
  @Post() create(
    @CurrentUser() user: Identity,
    @Body() dto: CreateCollectionDto,
  ) {
    return this.service.create(user.id, dto);
  }
  @Patch(':id') update(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCollectionDto,
  ) {
    return this.service.update(user.id, id, dto);
  }
}
