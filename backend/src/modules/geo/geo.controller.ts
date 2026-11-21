import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Type } from 'class-transformer';
import {
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsString,
  MaxLength,
  ValidateIf,
} from 'class-validator';
import { GeoService } from './geo.service';

export class SuggestQuery {
  @IsString() @MaxLength(200) q!: string;
  @ValidateIf((o: SuggestQuery) => o.lng !== undefined || o.lat !== undefined)
  @Type(() => Number)
  @IsNumber()
  @IsLatitude()
  lat?: number;
  @ValidateIf((o: SuggestQuery) => o.lng !== undefined || o.lat !== undefined)
  @Type(() => Number)
  @IsNumber()
  @IsLongitude()
  lng?: number;
}
export class ReverseQuery {
  @Type(() => Number) @IsNumber() @IsLatitude() lat!: number;
  @Type(() => Number) @IsNumber() @IsLongitude() lng!: number;
}

/** Signed-in customers only, so the shop's quota is not open to the web. */
@ApiTags('geo')
@ApiBearerAuth()
@Controller('geo')
@Throttle({ default: { limit: 60, ttl: 60000 } })
export class GeoController {
  constructor(private readonly service: GeoService) {}
  @Get('suggest') suggest(@Query() q: SuggestQuery) {
    return this.service.suggest(
      q.q,
      q.lat !== undefined && q.lng !== undefined
        ? { lat: q.lat, lng: q.lng }
        : undefined,
    );
  }
  @Get('reverse') async reverse(@Query() q: ReverseQuery) {
    return { place: await this.service.reverse(q.lat, q.lng) };
  }
}
