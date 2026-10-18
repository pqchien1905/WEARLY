import { ApiProperty } from '@nestjs/swagger';
import {
  Equals,
  IsBoolean,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';
export class TryOnDto {
  @ApiProperty() @IsUUID() imageId!: string;
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(100) sku!: string;
  @ApiProperty({ enum: [true] }) @IsBoolean() @Equals(true) consent!: boolean;
}
