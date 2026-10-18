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
import {
  AdjustInventoryDto,
  CategoryDto,
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
  constructor(private readonly service: AdminService) {}
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
    return this.service.category(dto);
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
