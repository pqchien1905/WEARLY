import { Controller, Get, Header, Param } from '@nestjs/common';
import { Public } from '../../common/decorators/auth';
import { StorefrontService } from './storefront.service';

@Public()
@Controller('storefront')
export class StorefrontController {
  constructor(private readonly service: StorefrontService) {}
  @Get('products/:slug')
  @Header('Content-Type', 'text/html; charset=utf-8')
  product(@Param('slug') slug: string) {
    return this.service.product(slug);
  }
  @Get('sitemap.xml')
  @Header('Content-Type', 'application/xml; charset=utf-8')
  sitemap() {
    return this.service.sitemap();
  }
  @Get('robots.txt')
  @Header('Content-Type', 'text/plain; charset=utf-8')
  robots() {
    return '# Local preview only. Pages send noindex headers.\nUser-agent: *\nDisallow:\n';
  }
}
