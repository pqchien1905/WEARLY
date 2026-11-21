import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  Matches,
  Max,
  Min,
  IsString,
  MaxLength,
  IsArray,
  ArrayMaxSize,
  ArrayUnique,
  IsUUID,
  ValidateIf,
} from 'class-validator';
export class PromotionFieldsDto {
  @IsIn(['CODE', 'AUTOMATIC']) application: 'CODE' | 'AUTOMATIC' = 'CODE';
  @IsIn(['ALL', 'PRODUCTS']) scope: 'ALL' | 'PRODUCTS' = 'ALL';
  @IsString() @MaxLength(120) name: string = '';
  @IsArray()
  @ArrayMaxSize(1000)
  @ArrayUnique()
  @IsUUID('all', { each: true })
  productIds: string[] = [];
  @IsIn(['FIXED', 'PERCENT']) kind!: 'FIXED' | 'PERCENT';
  @Matches(/^[1-9]\d{0,13}$/) amount!: string;
  @IsBoolean() active: boolean = false;
  @IsOptional()
  @IsISO8601({ strict: true })
  @Matches(/(Z|[+-]\d{2}:\d{2})$/)
  startsAt?: string | null;
  @IsOptional()
  @IsISO8601({ strict: true })
  @Matches(/(Z|[+-]\d{2}:\d{2})$/)
  expiresAt?: string | null;
  @Matches(/^\d{1,14}$/) minSubtotal: string = '0';
  @IsOptional() @Matches(/^[1-9]\d{0,13}$/) maxDiscount?: string | null;
  @IsOptional() @IsInt() @Min(1) @Max(2147483647) usageLimit?: number | null;
  @IsInt() @Min(1) @Max(2147483647) perUserLimit: number = 1;
}
export class CreatePromotionDto extends PromotionFieldsDto {
  @ValidateIf((o, v) => o.application !== 'AUTOMATIC' || v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @Matches(/^[A-Z0-9_-]{3,32}$/)
  code?: string;
}
export class UpdatePromotionDto {
  @IsOptional() @IsIn(['CODE', 'AUTOMATIC']) application?: 'CODE' | 'AUTOMATIC';
  @IsOptional() @IsIn(['ALL', 'PRODUCTS']) scope?: 'ALL' | 'PRODUCTS';
  @IsOptional() @IsString() @MaxLength(120) name?: string;
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(1000)
  @ArrayUnique()
  @IsUUID('all', { each: true })
  productIds?: string[];
  @IsInt() @Min(0) expectedVersion!: number;
  @IsOptional() @IsIn(['FIXED', 'PERCENT']) kind?: 'FIXED' | 'PERCENT';
  @IsOptional() @Matches(/^[1-9]\d{0,13}$/) amount?: string;
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional()
  @IsISO8601({ strict: true })
  @Matches(/(Z|[+-]\d{2}:\d{2})$/)
  startsAt?: string | null;
  @IsOptional()
  @IsISO8601({ strict: true })
  @Matches(/(Z|[+-]\d{2}:\d{2})$/)
  expiresAt?: string | null;
  @IsOptional() @Matches(/^\d{1,14}$/) minSubtotal?: string;
  @IsOptional() @Matches(/^[1-9]\d{0,13}$/) maxDiscount?: string | null;
  @IsOptional() @IsInt() @Min(1) @Max(2147483647) usageLimit?: number | null;
  @IsOptional() @IsInt() @Min(1) @Max(2147483647) perUserLimit?: number;
}
export class PreviewPromotionDto {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @Matches(/^[A-Z0-9_-]{3,32}$/)
  code!: string;
  @IsIn(['standard', 'express']) shippingMethod: 'standard' | 'express' =
    'standard';
  @IsInt() @Min(0) cartVersion!: number;
}
