import { ApiProperty } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { StoreDetailsDto } from './store-details';
import {
  IsInt,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
  IsObject,
  ValidateIf,
  ValidateNested,
} from 'class-validator';

export class ContentVersionDto {
  @ApiProperty()
  @IsInt()
  @Min(0)
  @Max(2147483646)
  expectedVersion!: number;
}

export class SaveContentDto extends ContentVersionDto {
  @ValidateIf((_object: unknown, value: unknown) => value !== undefined)
  @IsObject()
  @ValidateNested()
  @Type(() => StoreDetailsDto)
  details?: StoreDetailsDto;

  @ApiProperty()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  banner!: string;

  @ApiProperty()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(1)
  @MaxLength(5000)
  policy!: string;
}
