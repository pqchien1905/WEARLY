import { Transform } from 'class-transformer';
import { IsEmail, IsString, MaxLength, MinLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
export class LoginDto {
  @ApiProperty({ example: 'customer@example.com' })
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsEmail()
  @MaxLength(254)
  email!: string;
  @ApiProperty({ minLength: 12, maxLength: 128 })
  @IsString()
  @MinLength(12)
  @MaxLength(128)
  password!: string;
}
export class RegisterDto extends LoginDto {
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(100) name!: string;
}
export class RefreshDto {
  @ApiProperty()
  @IsString()
  @MinLength(20)
  @MaxLength(2048)
  refreshToken!: string;
}
