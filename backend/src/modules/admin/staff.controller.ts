import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Admin, CurrentUser, Identity } from '../../common/decorators/auth';
import { StaffService } from './staff.service';
import { StaffQueryDto, UpdateStaffDto } from './staff.dto';
@Admin()
@ApiBearerAuth()
@ApiTags('staff')
@Controller('admin/staff')
export class StaffController {
  constructor(private readonly staff: StaffService) {}
  @Get() list(@Query() query: StaffQueryDto) {
    return this.staff.list(query);
  }
  @Patch(':id') update(
    @CurrentUser() actor: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateStaffDto,
  ) {
    return this.staff.update(actor.id, id, dto);
  }
}
