import { Module } from '@nestjs/common';
import { GeoController } from './geo.controller';
import { GEO_HTTP, GeoService } from './geo.service';

@Module({
  controllers: [GeoController],
  providers: [{ provide: GEO_HTTP, useValue: fetch }, GeoService],
})
export class GeoModule {}
