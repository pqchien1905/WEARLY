import { Transform } from 'class-transformer';
import {
  IsIn,
  IsString,
  MaxLength,
  MinLength,
  ValidateIf,
} from 'class-validator';
import { AdminPageDto as PageDto } from '../../../common/admin-page.dto';

export class CollectionSearchDto extends PageDto {
  @ValidateIf((_, v) => v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(100)
  q?: string;
}
export class AdminCollectionsQueryDto extends CollectionSearchDto {
  override limit = 10;
  @ValidateIf((_, v) => v !== undefined)
  @IsIn(['published', 'hidden', 'waiting'])
  status?: string;
  @IsIn([
    'position',
    'newest',
    'updated',
    'title_asc',
    'title_desc',
    'products_desc',
  ])
  sort = 'position';
}
export class CollectionCoverQueryDto extends CollectionSearchDto {
  @IsString() @MinLength(1) @MaxLength(100) style!: string;
}
