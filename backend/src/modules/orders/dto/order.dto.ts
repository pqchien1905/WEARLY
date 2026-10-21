import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsInt, ValidateIf, IsUUID, Matches, Min } from 'class-validator';
export class CreateOrderDto {
  @ApiProperty() @IsUUID() addressId!: string;
  @ApiProperty({ enum: ['standard', 'express'] })
  @IsIn(['standard', 'express'])
  shippingMethod: 'standard' | 'express' = 'standard';
  @ApiProperty({ enum: ['cod', 'vnpay'] })
  @IsIn(['cod', 'vnpay'])
  paymentMethod: 'cod' | 'vnpay' = 'cod';
  @ApiProperty({
    description: 'Exact VND subtotal from the last cart response',
  })
  @Matches(/^\d{1,14}$/)
  expectedSubtotal!: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsInt()
  @Min(0)
  cartVersion?: number;
}
