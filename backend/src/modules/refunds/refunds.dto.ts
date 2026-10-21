import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsInt,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
} from 'class-validator';
const lower = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.toLowerCase() : value;
export class CreateRefundDto {
  @ApiProperty() @Transform(lower) @IsUUID() requestKey!: string;
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
  @ApiProperty() @Matches(/^[1-9]\d{0,13}$/) expectedAmount!: string;
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @Transform(lower)
  @IsUUID()
  paymentAttemptId?: string;
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(3)
  @MaxLength(100)
  reference?: string;
}
export class QueryRefundDto {
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @Matches(/^[1-9]\d{0,14}$/)
  transactionNo?: string;
}
