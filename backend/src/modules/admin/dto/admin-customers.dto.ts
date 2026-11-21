import { Transform } from 'class-transformer';
import { IntersectionType } from '@nestjs/swagger';
import {
  IsBoolean,
  IsDateString,
  IsEmail,
  IsIn,
  IsString,
  MaxLength,
  MinLength,
  Matches,
  ValidateIf,
} from 'class-validator';
import { AdminPageDto as PageDto } from '../../../common/admin-page.dto';
import { ProfileDto } from '../../users/dto/user.dto';
import { LoginDto } from '../../auth/dto/auth.dto';
import { normalizePhone } from '../../users/profile-identity';

export class CustomerAdminAccessDto {
  @ValidateIf((_o, v) => v !== undefined)
  @IsBoolean()
  adminAccess?: boolean;

  @ValidateIf(
    (o: CustomerAdminAccessDto, v) => o.adminAccess === true || v !== undefined,
  )
  @IsIn(['ADMIN', 'MANAGER', 'WAREHOUSE', 'SUPPORT'])
  adminRole?: 'ADMIN' | 'MANAGER' | 'WAREHOUSE' | 'SUPPORT';

  @ValidateIf(
    (o: CustomerAdminAccessDto, v) => o.adminAccess === true || v !== undefined,
  )
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsString()
  @Matches(/^[a-z0-9][a-z0-9_.-]{2,63}$/)
  username?: string;
}

export class CreateCustomerDto extends IntersectionType(
  LoginDto,
  CustomerAdminAccessDto,
) {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name!: string;

  @ValidateIf((_o, v) => v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? normalizePhone(value) : value,
  )
  @IsString()
  @MaxLength(30)
  @Matches(/^(?:\+?\d{7,15})?$/)
  phone?: string;
}

export class DeleteCustomerDto {
  @IsDateString({ strict: true }) expectedUpdatedAt!: string;
}

export class AdminCustomersQueryDto extends PageDto {
  override limit = 10;
  @ValidateIf((_o, v) => v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(100)
  q?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['active', 'hidden'])
  status?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['newest', 'oldest', 'name_asc', 'name_desc', 'orders_desc'])
  sort?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['has_orders', 'no_orders'])
  orders?: string;
  @ValidateIf((_o, v) => v !== undefined)
  @IsIn(['30d'])
  registered?: string;
}
export class UpdateCustomerDto extends IntersectionType(
  ProfileDto,
  CustomerAdminAccessDto,
) {
  @IsDateString({ strict: true }) expectedUpdatedAt!: string;
  @ValidateIf((_o, v) => v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsEmail()
  @MaxLength(254)
  email?: string;
}
export class CustomerStatusDto {
  @IsDateString({ strict: true }) expectedUpdatedAt!: string;
  @IsBoolean() active!: boolean;
}

export class ResetCustomerPasswordDto {
  @IsDateString({ strict: true }) expectedUpdatedAt!: string;
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password!: string;
}
