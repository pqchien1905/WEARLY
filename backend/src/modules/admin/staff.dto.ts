import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsEmail,
  IsEnum,
  IsInt,
  Max,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
import { Role } from '../../generated/prisma/client';
import { AdminPageDto as PageDto } from '../../common/admin-page.dto';
export class StaffQueryDto extends PageDto {
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsEmail()
  @MaxLength(254)
  email?: string;
}
export class UpdateStaffDto {
  @IsInt() @Min(0) @Max(2147483647) expectedVersion!: number;
  @IsEnum(Role) role!: Role;
  @IsBoolean() active!: boolean;
}
