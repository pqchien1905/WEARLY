import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { TaxonomyService } from './taxonomy.service';
import { ShipmentsModule } from '../shipments/shipments.module';
import { StaffController } from './staff.controller';
import { StaffService } from './staff.service';
@Module({
  imports: [ShipmentsModule],
  controllers: [AdminController, StaffController],
  providers: [AdminService, TaxonomyService, StaffService],
})
export class AdminModule {}
