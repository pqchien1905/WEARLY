import { ApiProperty, PartialType } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { normalizePhone } from '../profile-identity';
import {
  IsBoolean,
  ValidateIf,
  IsString,
  MaxLength,
  MinLength,
  Matches,
  IsLatitude,
  IsNumber,
  IsLongitude,
} from 'class-validator';
export class ProfileDto {
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name?: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? normalizePhone(value) : value,
  )
  @IsString()
  @MaxLength(30)
  @Matches(/^(?:\+?\d{7,15})?$/)
  phone?: string;
}
export class AddressDto {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  recipient!: string;
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @ApiProperty()
  @IsString()
  @Matches(/^0\d{9}$/)
  phone!: string;
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @ApiProperty()
  @IsString()
  @MinLength(8)
  @MaxLength(500)
  address!: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(50)
  label?: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsBoolean()
  isDefault?: boolean;
  /** Map pin. Send both or neither; null clears an existing pin. */
  @ApiProperty({ required: false, nullable: true })
  @ValidateIf((_object, value) => value !== undefined && value !== null)
  @IsNumber()
  @IsLatitude()
  latitude?: number | null;
  @ApiProperty({ required: false, nullable: true })
  @ValidateIf((_object, value) => value !== undefined && value !== null)
  @IsNumber()
  @IsLongitude()
  longitude?: number | null;
}
export class UpdateAddressDto extends PartialType(AddressDto, {
  skipNullProperties: false,
}) {}
