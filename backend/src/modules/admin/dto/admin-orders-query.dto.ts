import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsDateString,
  IsIn,
  IsString,
  Matches,
  MaxLength,
  ValidateIf,
  IsUUID,
} from 'class-validator';
import { AdminPageDto as PageDto } from '../../../common/admin-page.dto';

export class AdminOrdersQueryDto extends PageDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsIn(['live', 'test', 'all'])
  dataKind?: string;
  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsUUID()
  customerId?: string;
  @ApiPropertyOptional({ default: 20 })
  override limit = 10;

  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(100)
  q?: string;

  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsIn([
    'PENDING',
    'CONFIRMED',
    'SHIPPED',
    'DELIVERED',
    'CANCELLED',
    'RETURNED',
  ])
  status?: string;

  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsIn(['cod', 'vnpay', 'momo', 'zalopay', 'free'])
  provider?: string;

  @ApiPropertyOptional()
  @ValidateIf((_object, value) => value !== undefined)
  @IsIn([
    'PENDING',
    'PAID',
    'PARTIALLY_REFUNDED',
    'REFUNDED',
    'FAILED',
    'CANCELLED',
    'COD_UNSETTLED',
  ])
  paymentStatus?: string;

  @ApiPropertyOptional({
    description: 'Inclusive calendar date in UTC+7, YYYY-MM-DD',
  })
  @ValidateIf((_object, value) => value !== undefined)
  @Matches(/^20\d{2}-\d{2}-\d{2}$/)
  @IsDateString({ strict: true })
  from?: string;

  @ApiPropertyOptional({
    description: 'Inclusive calendar date in UTC+7, YYYY-MM-DD',
  })
  @ValidateIf((_object, value) => value !== undefined)
  @Matches(/^20\d{2}-\d{2}-\d{2}$/)
  @IsDateString({ strict: true })
  to?: string;

  @ApiPropertyOptional({ default: 'newest' })
  @ValidateIf((_object, value) => value !== undefined)
  @IsIn(['newest', 'oldest', 'total_desc', 'total_asc'])
  sort?: string;
}
