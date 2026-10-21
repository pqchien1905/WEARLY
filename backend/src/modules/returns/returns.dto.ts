import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
  ValidateNested,
} from 'class-validator';
const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;
export class ReturnItemDto {
  @ApiProperty()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.toLowerCase() : value,
  )
  @IsUUID()
  orderItemId!: string;
  @ApiProperty() @IsInt() @Min(1) quantity!: number;
}
export class QuoteReturnDto {
  @ApiProperty({ type: [ReturnItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => ReturnItemDto)
  items!: ReturnItemDto[];
}
export class CreateReturnDto extends QuoteReturnDto {
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @Matches(/^\d{1,14}$/)
  expectedAmount?: string;
  @ApiProperty()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.toLowerCase() : value,
  )
  @IsUUID()
  requestKey!: string;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(3)
  @MaxLength(300)
  reason!: string;
}
export class ReceiveReturnDto {
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @Transform(trim)
  @IsString()
  @MaxLength(300)
  note = '';
}
export class DecideReturnDto extends ReceiveReturnDto {
  @ApiProperty({ enum: ['APPROVED', 'REJECTED'] })
  @IsIn(['APPROVED', 'REJECTED'])
  status!: 'APPROVED' | 'REJECTED';
}
export class AdminCancelDto {
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(3)
  @MaxLength(300)
  reason!: string;
}
