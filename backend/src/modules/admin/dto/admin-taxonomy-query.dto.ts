import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsIn, IsString, MaxLength, ValidateIf } from 'class-validator';
import { AdminPageDto as PageDto } from '../../../common/admin-page.dto';

export class AdminTaxonomyQueryDto extends PageDto {
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(100)
  q?: string;

  @ApiPropertyOptional({
    enum: ['empty', 'populated', 'published', 'unpublished'],
  })
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['empty', 'populated', 'published', 'unpublished'])
  coverage?: string;

  @ApiPropertyOptional({ default: 'name_asc' })
  @IsIn([
    'name_asc',
    'name_desc',
    'newest',
    'oldest',
    'updated',
    'products_asc',
    'products_desc',
  ])
  sort = 'name_asc';
}
