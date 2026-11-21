import { ApiPropertyOptional } from '@nestjs/swagger';
import { PageDto } from '../modules/products/dto/query-products.dto';

/** Administrative lists have a single default, separate from the storefront. */
export class AdminPageDto extends PageDto {
  @ApiPropertyOptional({ default: 10, minimum: 1, maximum: 100 })
  override limit = 10;
}
