import { Controller, Get, Header } from '@nestjs/common';
import { Admin } from '../../common/decorators/auth';
import { OperationsService } from './operations.service';

@Admin('staff.manage')
@Controller('admin/operations')
export class OperationsController {
  constructor(private readonly operations: OperationsService) {}
  @Get()
  @Header('Cache-Control', 'private, no-store')
  snapshot() {
    return this.operations.snapshot();
  }
}
