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
import { Admin, CurrentUser, Identity } from '../../common/decorators/auth';
import { AdminPageDto as PageDto } from '../../common/admin-page.dto';
import { AdminService } from './admin.service';
import { OrderClassificationDto } from './dto/order-classification.dto';
import { AdminOrdersQueryDto } from './dto/admin-orders-query.dto';
import { AdminProductsQueryDto } from './dto/admin-products-query.dto';
import {
  AdminInventoryQueryDto,
  InventoryHistoryQueryDto,
} from './dto/admin-inventory-query.dto';
import { TaxonomyService } from './taxonomy.service';
import { AdminTaxonomyQueryDto } from './dto/admin-taxonomy-query.dto';
import { AdminCategoriesQueryDto } from './dto/admin-categories-query.dto';
import { CustomersService } from './customers.service';
import {
  AdminCustomersQueryDto,
  CreateCustomerDto,
  DeleteCustomerDto,
  CustomerStatusDto,
  ResetCustomerPasswordDto,
  UpdateCustomerDto,
} from './dto/admin-customers.dto';
import {
  AdjustInventoryDto,
  CategoryDto,
  DeleteCategoryDto,
  DeleteTaxonomyDto,
  RenameTaxonomyDto,
  CreateProductDto,
  DeleteProductDto,
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
    private readonly customers: CustomersService,
  ) {}
  @Admin('payments.manage')
  @Patch('orders/:id/classification')
  classify(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: OrderClassificationDto,
  ) {
    return this.service.classify(u.id, id, dto);
  }
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
  @Get('products/summary')
  productsSummary() {
    return this.service.productsSummary();
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
  products(@Query() q: AdminProductsQueryDto) {
    return this.service.products(q);
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
  @Delete('products/:id')
  deleteProduct(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DeleteProductDto,
  ) {
    return this.service.deleteProduct(u.id, id, dto.expectedUpdatedAt);
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
  categories(@Query() q: AdminCategoriesQueryDto) {
    return this.taxonomy.categories(q);
  }
  @Admin('catalog.read')
  @Get('categories/summary')
  categoriesSummary() {
    return this.taxonomy.categorySummary();
  }
  @Admin('catalog.read')
  @Get('categories/:id')
  categoryDetail(@Param('id', ParseUUIDPipe) id: string) {
    return this.taxonomy.categoryDetail(id);
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
  @Delete('categories/:id')
  deleteCategory(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DeleteCategoryDto,
  ) {
    return this.taxonomy.deleteCategory(u.id, id, dto.expectedUpdatedAt);
  }
  @Admin('catalog.write')
  @Post('brands')
  brand(@CurrentUser() u: Identity, @Body() dto: CategoryDto) {
    return this.taxonomy.create(u.id, 'brands', dto);
  }
  @Admin('catalog.read')
  @Get('brands')
  brands(@Query() q: AdminTaxonomyQueryDto) {
    return this.taxonomy.brands(q);
  }
  @Admin('catalog.read')
  @Get('brands/summary')
  brandsSummary() {
    return this.taxonomy.brandSummary();
  }
  @Admin('catalog.read')
  @Get('brands/:id')
  brandDetail(@Param('id', ParseUUIDPipe) id: string) {
    return this.taxonomy.brandDetail(id);
  }
  @Admin('catalog.write')
  @Delete('brands/:id')
  deleteBrand(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DeleteTaxonomyDto,
  ) {
    return this.taxonomy.deleteBrand(u.id, id, dto.expectedUpdatedAt);
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
  @Get('inventory/summary')
  inventorySummary() {
    return this.service.inventorySummary();
  }
  @Admin('inventory.read')
  @Get('inventory/:id/movements')
  inventoryHistory(
    @Param('id', ParseUUIDPipe) id: string,
    @Query() q: InventoryHistoryQueryDto,
  ) {
    return this.service.inventoryHistory(id, q);
  }
  @Admin('inventory.read')
  @Get('inventory/:id')
  inventoryDetail(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.inventoryDetail(id);
  }
  @Admin('inventory.write')
  @Post('inventory/variants/:id/initialize')
  initializeInventory(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.initializeInventory(u.id, id);
  }
  @Admin('inventory.read')
  @Get('inventory')
  inventory(@Query() q: AdminInventoryQueryDto) {
    return this.service.inventory(q);
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
  orders(@Query() q: AdminOrdersQueryDto) {
    return this.service.orders(q);
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
  users(@Query() q: AdminCustomersQueryDto) {
    return this.customers.list(q);
  }
  @Admin('customers.manage')
  @Post('users')
  createCustomer(@CurrentUser() u: Identity, @Body() dto: CreateCustomerDto) {
    return this.customers.create(u.id, dto);
  }
  @Admin('customers.manage')
  @Delete('users/:id')
  deleteCustomer(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DeleteCustomerDto,
  ) {
    return this.customers.remove(u.id, id, dto);
  }
  @Admin('customers.read')
  @Get('users/summary')
  customerSummary() {
    return this.customers.summary();
  }
  @Admin('customers.read')
  @Get('users/:id')
  customer(@Param('id', ParseUUIDPipe) id: string) {
    return this.customers.detail(id);
  }
  @Admin('customers.manage')
  @Patch('users/:id')
  updateCustomer(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCustomerDto,
  ) {
    return this.customers.update(u.id, id, dto);
  }
  @Admin('customers.manage')
  @Post('users/:id/reset-password')
  resetCustomerPassword(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ResetCustomerPasswordDto,
  ) {
    return this.customers.resetPassword(u.id, id, dto);
  }
  @Admin('customers.manage')
  @Patch('users/:id/status')
  customerStatus(
    @CurrentUser() u: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CustomerStatusDto,
  ) {
    return this.customers.update(u.id, id, dto);
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
