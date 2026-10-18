import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  ValidateIf,
  IsString,
  Max,
  MaxLength,
  Min,
  Matches,
} from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
export class PageDto {
  @ApiPropertyOptional({ default: 1 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10000)
  page = 1;
  @ApiPropertyOptional({ default: 12 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 12;
}
export class QueryProductsDto extends PageDto {
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(100)
  q?: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(100)
  category?: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(100)
  brand?: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(30)
  size?: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(60)
  color?: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(100)
  style?: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @Matches(/^\d{1,14}$/)
  minPrice?: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @Matches(/^\d{1,14}$/)
  maxPrice?: string;
  @ApiPropertyOptional({ enum: ['true', 'false'] })
  @ValidateIf((_object, value) => value !== undefined)
  @IsIn(['true', 'false'])
  inStock?: string;
  @ApiPropertyOptional({ enum: ['newest', 'price-asc', 'price-desc', 'name'] })
  @IsIn(['newest', 'price-asc', 'price-desc', 'name'])
  sort = 'newest';
}
