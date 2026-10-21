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
} from 'class-validator';
export class PromotionFieldsDto {
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
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @Matches(/^[A-Z0-9_-]{3,32}$/)
  code!: string;
}
export class UpdatePromotionDto {
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
