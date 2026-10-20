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
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Admin, CurrentUser, Identity } from '../../common/decorators/auth';
import { PageDto } from '../products/dto/query-products.dto';
import { AdminService } from './admin.service';
import { TaxonomyService } from './taxonomy.service';
import {
  AdjustInventoryDto,
  CategoryDto,
  RenameTaxonomyDto,
  CreateProductDto,
  CreateSkuDto,
  OrderStatusDto,
  UpdateProductDto,
  UpdateSkuDto,
} from './dto/admin.dto';
@Admin()
@ApiTags('admin')
@ApiBearerAuth()
@Controller('admin')
export class AdminController {
  constructor(
    private readonly service: AdminService,
    private readonly taxonomy: TaxonomyService,
  ) {}
  @Get('summary') summary() {
    return this.service.summary();
  }
  @Get('audit') audit(@Query() q: PageDto) {
    return this.service.audit(q);
  }
  @Get('products/:id') product(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.product(id);
  }
  @Get('orders/:id') order(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.order(id);
  }
  @Get('products') products(@Query() q: PageDto) {
    return this.service.list('products', q);
  }
  @Post('products') createProduct(
    @CurrentUser() u: Identity,
    @Body() dto: CreateProductDto,
  ) {
    return this.service.createProduct(u.id, dto);
  }
  @Patch('products/:id') updateProduct(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateProductDto,
  ) {
    return this.service.updateProduct(u.id, id, dto);
  }
  @Post('skus') createSku(
    @CurrentUser() u: Identity,
    @Body() dto: CreateSkuDto,
  ) {
    return this.service.createSku(u.id, dto);
  }
  @Patch('skus/:id') updateSku(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateSkuDto,
  ) {
    return this.service.updateSku(u.id, id, dto);
  }
  @Post('categories') category(
    @CurrentUser() u: Identity,
    @Body() dto: CategoryDto,
  ) {
    return this.taxonomy.create(u.id, 'categories', dto);
  }
  @Get('categories') categories(@Query() q: PageDto) {
    return this.taxonomy.list('categories', q);
  }
  @Patch('categories/:id') renameCategory(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RenameTaxonomyDto,
  ) {
    return this.taxonomy.rename(u.id, 'categories', id, dto);
  }
  @Post('brands') brand(@CurrentUser() u: Identity, @Body() dto: CategoryDto) {
    return this.taxonomy.create(u.id, 'brands', dto);
  }
  @Get('brands') brands(@Query() q: PageDto) {
    return this.taxonomy.list('brands', q);
  }
  @Patch('brands/:id') renameBrand(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RenameTaxonomyDto,
  ) {
    return this.taxonomy.rename(u.id, 'brands', id, dto);
  }
  @Get('inventory') inventory(@Query() q: PageDto) {
    return this.service.list('inventory', q);
  }
  @Post('inventory/:id/adjust') adjust(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdjustInventoryDto,
  ) {
    return this.service.adjust(u.id, id, dto);
  }
  @Get('orders') orders(@Query() q: PageDto) {
    return this.service.list('orders', q);
  }
  @Patch('orders/:id/status') status(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: OrderStatusDto,
  ) {
    return this.service.status(u.id, id, dto);
  }
  @Get('users') users(@Query() q: PageDto) {
    return this.service.list('users', q);
  }
}
