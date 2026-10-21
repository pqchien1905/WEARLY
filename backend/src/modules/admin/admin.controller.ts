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
  SettleCodDto,
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
  @Admin('reports.read')
  @Get('summary')
  summary() {
    return this.service.summary();
  }
  @Admin('audit.read')
  @Get('audit')
  audit(@Query() q: PageDto) {
    return this.service.audit(q);
  }
  @Admin('catalog.read')
  @Get('products/:id')
  product(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.product(id);
  }
  @Admin('orders.read')
  @Get('orders/:id')
  order(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.order(id);
  }
  @Admin('catalog.read')
  @Get('products')
  products(@Query() q: PageDto) {
    return this.service.list('products', q);
  }
  @Admin('catalog.write')
  @Post('products')
  createProduct(@CurrentUser() u: Identity, @Body() dto: CreateProductDto) {
    return this.service.createProduct(u.id, dto);
  }
  @Admin('catalog.write')
  @Patch('products/:id')
  updateProduct(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateProductDto,
  ) {
    return this.service.updateProduct(u.id, id, dto);
  }
  @Admin('catalog.write')
  @Post('skus')
  createSku(@CurrentUser() u: Identity, @Body() dto: CreateSkuDto) {
    return this.service.createSku(u.id, dto);
  }
  @Admin('catalog.write')
  @Patch('skus/:id')
  updateSku(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateSkuDto,
  ) {
    return this.service.updateSku(u.id, id, dto);
  }
  @Admin('catalog.write')
  @Post('categories')
  category(@CurrentUser() u: Identity, @Body() dto: CategoryDto) {
    return this.taxonomy.create(u.id, 'categories', dto);
  }
  @Admin('catalog.read')
  @Get('categories')
  categories(@Query() q: PageDto) {
    return this.taxonomy.list('categories', q);
  }
  @Admin('catalog.write')
  @Patch('categories/:id')
  renameCategory(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RenameTaxonomyDto,
  ) {
    return this.taxonomy.rename(u.id, 'categories', id, dto);
  }
  @Admin('catalog.write')
  @Post('brands')
  brand(@CurrentUser() u: Identity, @Body() dto: CategoryDto) {
    return this.taxonomy.create(u.id, 'brands', dto);
  }
  @Admin('catalog.read')
  @Get('brands')
  brands(@Query() q: PageDto) {
    return this.taxonomy.list('brands', q);
  }
  @Admin('catalog.write')
  @Patch('brands/:id')
  renameBrand(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RenameTaxonomyDto,
  ) {
    return this.taxonomy.rename(u.id, 'brands', id, dto);
  }
  @Admin('inventory.read')
  @Get('inventory')
  inventory(@Query() q: PageDto) {
    return this.service.list('inventory', q);
  }
  @Admin('inventory.write')
  @Post('inventory/:id/adjust')
  adjust(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdjustInventoryDto,
  ) {
    return this.service.adjust(u.id, id, dto);
  }
  @Admin('orders.read')
  @Get('orders')
  orders(@Query() q: PageDto) {
    return this.service.list('orders', q);
  }
  @Admin('orders.fulfill')
  @Patch('orders/:id/status')
  status(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: OrderStatusDto,
  ) {
    return this.service.status(u.id, id, dto);
  }
  @Admin('customers.read')
  @Get('users')
  users(@Query() q: PageDto) {
    return this.service.list('users', q);
  }
  @Admin('payments.manage')
  @Post('orders/:id/settle-cod')
  settleCod(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SettleCodDto,
  ) {
    return this.service.settleCod(u.id, id, dto);
  }
}
