import { Transform } from 'class-transformer';
import { IsEmail, IsString, Length, Matches, MaxLength } from 'class-validator';
export class ForgotPasswordDto {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsEmail()
  @MaxLength(254)
  email!: string;
}
export class ResetPasswordDto {
  @IsString()
  @Matches(/^[A-Za-z0-9_-]{43}$/)
  token!: string;
  @IsString()
  @Length(8, 128)
  password!: string;
}
export class ChangePasswordDto {
  @IsString()
  @Length(1, 128)
  currentPassword!: string;
  @IsString()
  @Length(8, 128)
  newPassword!: string;
}
export class VerifyResetCodeDto extends ForgotPasswordDto {
  @IsString()
  @Matches(/^\d{6}$/)
  code!: string;
}
