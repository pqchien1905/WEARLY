import { Transform } from 'class-transformer';
import { ApiProperty, OmitType, PartialType } from '@nestjs/swagger';
import {
  IsBoolean,
  IsInt,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
} from 'class-validator';
const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.normalize('NFKC').trim() : value;
export class CreateCollectionDto {
  @ApiProperty()
  @Transform(trim)
  @Matches(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
  @MaxLength(100)
  slug!: string;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  title!: string;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MaxLength(1500)
  description!: string;
  @ApiProperty()
  @Transform(trim)
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  style!: string;
  @ApiProperty({ required: false })
  @ValidateIf((_, v) => v !== undefined)
  @IsBoolean()
  active?: boolean;
  @ApiProperty({ required: false })
  @ValidateIf((_, v) => v !== undefined)
  @IsInt()
  @Min(0)
  @Max(10000)
  position?: number;
  @ApiProperty({ required: false, nullable: true })
  @ValidateIf((_, v) => v !== undefined && v !== null)
  @IsUUID()
  coverProductId?: string | null;
}
export class UpdateCollectionDto extends PartialType(
  OmitType(CreateCollectionDto, ['slug'] as const),
  { skipNullProperties: false },
) {
  @ApiProperty() @IsInt() @Min(1) expectedVersion!: number;
}

export class DeleteCollectionDto {
  @ApiProperty() @IsInt() @Min(1) @Max(2147483647) expectedVersion!: number;
}
