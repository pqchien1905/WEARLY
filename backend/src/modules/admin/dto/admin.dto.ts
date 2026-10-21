import { ApiProperty, PartialType } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsArray,
  ArrayMaxSize,
  ValidateNested,
  IsBoolean,
  IsIn,
  IsInt,
  ValidateIf,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
export class ProductImageDto {
  @ApiProperty()
  @IsString()
  @MaxLength(2000)
  @Matches(
    /^(https:\/\/[^\s]+|assets\/images\/[a-zA-Z0-9_./-]+|catalog\/images\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i,
  )
  url!: string;
  @ApiProperty() @IsString() @MaxLength(200) alt!: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(60)
  color?: string;
}
export class CreateProductDto {
  @ApiProperty()
  @Matches(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
  @MaxLength(100)
  slug!: string;
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(200) name!: string;
  @ApiProperty() @IsString() @MaxLength(5000) description!: string;
  @ApiProperty() @IsString() @MaxLength(200) material!: string;
  @ApiProperty() @IsString() @MaxLength(100) style!: string;
  @ApiProperty() @IsUUID() categoryId!: string;
  @ApiProperty() @IsUUID() brandId!: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsBoolean()
  active?: boolean;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsBoolean()
  tryOnSupported?: boolean;
  @ApiProperty({ required: false, type: [ProductImageDto] })
  @ValidateIf((_object, value) => value !== undefined)
  @IsArray()
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => ProductImageDto)
  images?: ProductImageDto[];
}
export class UpdateProductDto extends PartialType(CreateProductDto, {
  skipNullProperties: false,
}) {}
export class CreateSkuDto {
  @ApiProperty() @IsUUID() productId!: string;
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(100) sku!: string;
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(30) size!: string;
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(60) color!: string;
  @ApiProperty() @Matches(/^#[0-9a-fA-F]{6}$/) colorHex!: string;
  @ApiProperty() @Matches(/^\d{1,14}$/) price!: string;
}
export class UpdateSkuDto {
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @Matches(/^\d{1,14}$/)
  price?: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsBoolean()
  active?: boolean;
}
export class CategoryDto {
  @ApiProperty()
  @Matches(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
  @MaxLength(100)
  slug!: string;
  @ApiProperty()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name!: string;
}
export class RenameTaxonomyDto {
  @ApiProperty()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name!: string;
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  expectedName!: string;
}
export class AdjustInventoryDto {
  @ApiProperty() @IsInt() @Min(-1000000) @Max(1000000) delta!: number;
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
  @ApiProperty() @IsString() @MinLength(3) @MaxLength(200) reason!: string;
}
export class OrderStatusDto {
  @ApiProperty({ enum: ['CONFIRMED', 'SHIPPED', 'DELIVERED'] })
  @IsIn(['CONFIRMED', 'SHIPPED', 'DELIVERED'])
  status!: 'CONFIRMED' | 'SHIPPED' | 'DELIVERED';
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
}
export class SettleCodDto {
  @ApiProperty() @Matches(/^[1-9]\d{0,13}$/) amount!: string;
  @ApiProperty()
  @Transform(({ value }: { value: unknown }) => typeof value === 'string' ? value.trim() : value)
  @IsString() @MinLength(3) @MaxLength(100) reference!: string;
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
}
