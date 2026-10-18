import { ApiProperty, PartialType } from '@nestjs/swagger';
import {
  IsBoolean,
  ValidateIf,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
export class ProfileDto {
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name?: string;
  @ApiProperty({ required: false })
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MaxLength(30)
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
