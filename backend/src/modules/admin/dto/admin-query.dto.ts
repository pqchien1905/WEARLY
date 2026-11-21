import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsIn, IsString, MaxLength, ValidateIf } from 'class-validator';
import { AdminPageDto as PageDto } from '../../../common/admin-page.dto';

export class AdminListQueryDto extends PageDto {
  @ApiPropertyOptional({
    description: 'Search within the entire filtered list',
  })
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(100)
  q?: string;

  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsIn([
    'active',
    'hidden',
    'in_stock',
    'low',
    'out',
    'PENDING',
    'CONFIRMED',
    'SHIPPED',
    'DELIVERED',
    'CANCELLED',
    'RETURNED',
  ])
  status?: string;
}
