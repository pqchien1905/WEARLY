import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
import { ShipmentStatus } from '../../generated/prisma/client';
export class ShipmentEventDto {
  @ApiProperty()
  @Transform(({ value }: { value: unknown }) => typeof value === 'string' ? value.toLowerCase() : value)
  @IsUUID() eventKey!: string;
  @ApiProperty() @IsInt() @Min(0) expectedVersion!: number;
  @ApiProperty({ enum: ShipmentStatus })
  @IsIn(Object.values(ShipmentStatus))
  status!: ShipmentStatus;
  @ApiPropertyOptional()
  @ValidateIf((_o, v) => v !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(300)
  note: string = '';
}
