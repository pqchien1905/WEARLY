import { ApiProperty } from '@nestjs/swagger';
import { IsInt, IsString, Max, MaxLength, Min } from 'class-validator';
export class QuantityDto {
  @ApiProperty({ minimum: 1, maximum: 99 })
  @IsInt()
  @Min(1)
  @Max(99)
  quantity!: number;
}
export class AddCartItemDto extends QuantityDto {
  @ApiProperty() @IsString() @MaxLength(100) sku!: string;
}
