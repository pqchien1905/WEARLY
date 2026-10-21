import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { TaxonomyService } from './taxonomy.service';
import { ShipmentsModule } from '../shipments/shipments.module';
@Module({
  imports: [ShipmentsModule],
  controllers: [AdminController],
  providers: [AdminService, TaxonomyService],
})
export class AdminModule {}
