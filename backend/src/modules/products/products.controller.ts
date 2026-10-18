import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators/auth';
import { ProductsService } from './products.service';
import { QueryProductsDto } from './dto/query-products.dto';
@Public()
@ApiTags('catalog')
@Controller()
export class ProductsController {
  constructor(private readonly service: ProductsService) {}
  @Get('products') list(@Query() q: QueryProductsDto) {
    return this.service.list(q);
  }
  @Get('products/facets') facets() {
    return this.service.facets();
  }
  @Get('products/:slug') bySlug(@Param('slug') slug: string) {
    return this.service.bySlug(slug);
  }
  @Get('categories') categories() {
    return this.service.categories();
  }
  @Get('brands') brands() {
    return this.service.brands();
  }
}
