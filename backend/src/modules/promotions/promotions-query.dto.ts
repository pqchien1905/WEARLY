import { Transform } from 'class-transformer';
import {
  IsIn,
  IsOptional,
  IsInt,
  IsString,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
import { AdminPageDto as PageDto } from '../../common/admin-page.dto';

export class AdminPromotionsQueryDto extends PageDto {
  @IsOptional() @IsIn(['CODE', 'AUTOMATIC']) application?: 'CODE' | 'AUTOMATIC';
  @IsOptional() @IsIn(['ALL', 'PRODUCTS']) scope?: 'ALL' | 'PRODUCTS';
  override limit = 10;
  @ValidateIf((_, v) => v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @IsString()
  @MaxLength(100)
  q?: string;
  @ValidateIf((_, v) => v !== undefined)
  @IsIn(['active', 'scheduled', 'expired', 'exhausted', 'inactive'])
  status?: string;
  @ValidateIf((_, v) => v !== undefined)
  @IsIn(['FIXED', 'PERCENT'])
  kind?: string;
  @IsIn(['newest', 'updated', 'code_asc', 'expiry', 'usage_desc']) sort =
    'newest';
}
export class DeletePromotionDto {
  @IsInt() @Min(0) expectedVersion!: number;
}
