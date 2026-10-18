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
import { Admin } from '../../common/decorators/auth';
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
  @Get('products/:id') product(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.product(id);
  }
  @Get('orders/:id') order(@Param('id', ParseUUIDPipe) id: string) {
    return this.service.order(id);
  }
  @Get('products') products(@Query() q: PageDto) {
    return this.service.list('products', q);
  }
  @Post('products') createProduct(@Body() dto: CreateProductDto) {
    return this.service.createProduct(dto);
  }
  @Patch('products/:id') updateProduct(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateProductDto,
  ) {
    return this.service.updateProduct(id, dto);
  }
  @Post('skus') createSku(@Body() dto: CreateSkuDto) {
    return this.service.createSku(dto);
  }
  @Patch('skus/:id') updateSku(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateSkuDto,
  ) {
    return this.service.updateSku(id, dto);
  }
  @Post('categories') category(@Body() dto: CategoryDto) {
    return this.taxonomy.create('categories', dto);
  }
  @Get('categories') categories(@Query() q: PageDto) {
    return this.taxonomy.list('categories', q);
  }
  @Patch('categories/:id') renameCategory(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RenameTaxonomyDto,
  ) {
    return this.taxonomy.rename('categories', id, dto);
  }
  @Post('brands') brand(@Body() dto: CategoryDto) {
    return this.taxonomy.create('brands', dto);
  }
  @Get('brands') brands(@Query() q: PageDto) {
    return this.taxonomy.list('brands', q);
  }
  @Patch('brands/:id') renameBrand(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RenameTaxonomyDto,
  ) {
    return this.taxonomy.rename('brands', id, dto);
  }
  @Get('inventory') inventory(@Query() q: PageDto) {
    return this.service.list('inventory', q);
  }
  @Post('inventory/:id/adjust') adjust(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdjustInventoryDto,
  ) {
    return this.service.adjust(id, dto);
  }
  @Get('orders') orders(@Query() q: PageDto) {
    return this.service.list('orders', q);
  }
  @Patch('orders/:id/status') status(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: OrderStatusDto,
  ) {
    return this.service.status(id, dto);
  }
  @Get('users') users(@Query() q: PageDto) {
    return this.service.list('users', q);
  }
}
