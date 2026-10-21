import {
  Equals,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
export class StylistDto {
  @IsString() @MinLength(1) @MaxLength(1000) prompt!: string;
  @IsString() @MinLength(1) @MaxLength(20) size!: string;
  @IsOptional() @IsString() @MaxLength(80) style?: string;
  @IsOptional() @IsString() @MaxLength(80) color?: string;
  @IsInt() @Min(1) @Max(20000000) budget!: number;
  @IsBoolean() @Equals(true) consent!: boolean;
}
