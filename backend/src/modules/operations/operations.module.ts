import { Module } from '@nestjs/common';
import { OperationsController } from './operations.controller';
import { OperationsService } from './operations.service';
import {
  OperationsProbes,
  operationsResourcesProvider,
} from './operations.probes';

@Module({
  controllers: [OperationsController],
  providers: [OperationsService, OperationsProbes, operationsResourcesProvider],
})
export class OperationsModule {}
