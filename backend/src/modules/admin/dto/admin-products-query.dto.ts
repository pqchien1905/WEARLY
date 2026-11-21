import {
  IsString,
  MaxLength,
  IsIn,
  IsUUID,
  Matches,
  ValidateIf,
} from 'class-validator';
import { AdminListQueryDto } from './admin-query.dto';

export class AdminProductsQueryDto extends AdminListQueryDto {
  @ValidateIf((_, v) => v !== undefined)
  @IsString()
  @MaxLength(100)
  style?: string;
  override limit = 10;
  @ValidateIf((_o, v) => v !== undefined)
  @IsUUID()
  categoryId?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsUUID()
  brandId?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @Matches(/^\d{1,14}$/)
  minPrice?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @Matches(/^\d{1,14}$/)
  maxPrice?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['in_stock', 'low', 'out', 'no_variants'])
  stock?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['published', 'incomplete'])
  visibility?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn([
    'newest',
    'oldest',
    'updated',
    'name_asc',
    'name_desc',
    'price_asc',
    'price_desc',
    'stock_asc',
    'stock_desc',
  ])
  sort?: string;
}
