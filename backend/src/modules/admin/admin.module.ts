import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { TaxonomyService } from './taxonomy.service';
@Module({
  controllers: [AdminController],
  providers: [AdminService, TaxonomyService],
})
export class AdminModule {}
