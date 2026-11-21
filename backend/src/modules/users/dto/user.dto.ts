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
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(100) recipient!: string;
  @ApiProperty() @IsString() @MinLength(7) @MaxLength(30) phone!: string;
  @ApiProperty() @IsString() @MinLength(5) @MaxLength(500) address!: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(50)
  label?: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsBoolean()
  isDefault?: boolean;
}
export class UpdateAddressDto extends PartialType(AddressDto, {
  skipNullProperties: false,
}) {}
