import {
  IsDateString,
  IsIn,
  IsUUID,
  Matches,
  ValidateIf,
} from 'class-validator';
import { AdminListQueryDto } from './admin-query.dto';
import { AdminPageDto as PageDto } from '../../../common/admin-page.dto';

export class AdminInventoryQueryDto extends AdminListQueryDto {
  override limit = 10;
  @ValidateIf((_o, v) => v !== undefined) @IsUUID() categoryId?: string;
  @ValidateIf((_o, v) => v !== undefined) @IsUUID() brandId?: string;
  @ValidateIf((_o, v) => v !== undefined) @IsUUID() productId?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @Matches(/^\d{1,10}$/)
  minQuantity?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @Matches(/^\d{1,10}$/)
  maxQuantity?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['all', 'active', 'hidden'])
  visibility?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['existing', 'missing'])
  record?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn([
    'newest',
    'updated',
    'sku_asc',
    'name_asc',
    'quantity_asc',
    'quantity_desc',
    'attention',
  ])
  sort?: string;
}
export class InventoryHistoryQueryDto extends PageDto {
  override limit = 10;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['in', 'out', 'admin', 'order', 'cancel', 'return'])
  type?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @Matches(/^20\d{2}-\d{2}-\d{2}$/)
  @IsDateString({ strict: true })
  from?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @Matches(/^20\d{2}-\d{2}-\d{2}$/)
  @IsDateString({ strict: true })
  to?: string;
}
