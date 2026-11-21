import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { AdminPageDto } from '../../common/admin-page.dto';
import {
  IsEmail,
  IsIn,
  IsInt,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
} from 'class-validator';
const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;
const lower = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim().toLowerCase() : value;
export class CreateSupportDto {
  @ApiProperty() @Transform(lower) @IsUUID() requestKey!: string;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  name!: string;
  @ApiProperty() @Transform(lower) @IsEmail() @MaxLength(254) email!: string;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(10)
  @MaxLength(3000)
  message!: string;
}
export class ReplySupportDto {
  @ApiProperty() @Transform(lower) @IsUUID() requestKey!: string;
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(3)
  @MaxLength(3000)
  message!: string;
}
export class StatusSupportDto {
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
  @ApiProperty({ enum: ['OPEN', 'CLOSED'] }) @IsIn(['OPEN', 'CLOSED']) status!:
    'OPEN' | 'CLOSED';
}
/** Name and email come from the signed-in account, not the request. */
export class CustomerSupportDto {
  @ApiProperty() @Transform(lower) @IsUUID() requestKey!: string;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(10)
  @MaxLength(3000)
  message!: string;
}
export class CustomerFollowUpDto {
  @ApiProperty() @Transform(lower) @IsUUID() requestKey!: string;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(3)
  @MaxLength(3000)
  message!: string;
}
export class CustomerSupportPageDto {
  @ApiPropertyOptional({ default: 1 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10000)
  page = 1;
  @ApiPropertyOptional({ default: 10 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  limit = 10;
}
export class ListSupportDto extends AdminPageDto {
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @IsUUID()
  cursor?: string;
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @IsUUID()
  userId?: string;
  @ApiPropertyOptional({ enum: ['OPEN', 'ANSWERED', 'CLOSED'] })
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['OPEN', 'ANSWERED', 'CLOSED'])
  status?: 'OPEN' | 'ANSWERED' | 'CLOSED';
}
