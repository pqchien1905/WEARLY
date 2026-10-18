import { ApiProperty, PartialType } from '@nestjs/swagger';
import {
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
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(100) name!: string;
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
