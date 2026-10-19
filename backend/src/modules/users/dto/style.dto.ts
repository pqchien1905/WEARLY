import { ApiProperty } from '@nestjs/swagger';
import { IsIn, IsInt, Max, Min } from 'class-validator';

export class SaveStyleDto {
  @ApiProperty({ enum: ['XS', 'S', 'M', 'L', 'XL', 'XXL'] })
  @IsIn(['XS', 'S', 'M', 'L', 'XL', 'XXL'])
  size!: string;

  @ApiProperty({ enum: ['', 'Tối giản', 'Thanh lịch', 'Thư giãn'] })
  @IsIn(['', 'Tối giản', 'Thanh lịch', 'Thư giãn'])
  style!: string;

  @ApiProperty({
    enum: ['', 'Trắng', 'Đen', 'Mận', 'Xanh', 'Nâu', 'Hồng đất', 'Tím', 'Đỏ'],
  })
  @IsIn(['', 'Trắng', 'Đen', 'Mận', 'Xanh', 'Nâu', 'Hồng đất', 'Tím', 'Đỏ'])
  color!: string;

  @ApiProperty({ enum: ['800000', '1500000', '2500000'] })
  @IsIn(['800000', '1500000', '2500000'])
  budget!: string;

  @ApiProperty({ minimum: 0 })
  @IsInt()
  @Min(0)
  @Max(2147483646)
  expectedVersion!: number;
}
