import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Equals } from 'class-validator';
import { CurrentUser, Identity } from '../../common/decorators/auth';
import { MAX_IMAGE_BYTES } from '../../integrations/storage/image-policy';
import { UploadsService } from './uploads.service';
import { ImageLifecycleService } from './image-lifecycle.service';
class UploadConsentDto {
  @Equals('true') consent!: string;
}
@ApiTags('uploads')
@ApiBearerAuth()
@Controller('uploads/images')
export class UploadsController {
  constructor(
    private readonly service: UploadsService,
    private readonly lifecycle: ImageLifecycleService,
  ) {}
  @Post()
  @Throttle({ default: { limit: 30, ttl: 60000 } })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      required: ['file', 'consent'],
      properties: {
        file: { type: 'string', format: 'binary' },
        consent: { type: 'string', enum: ['true'] },
      },
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      limits: {
        fileSize: MAX_IMAGE_BYTES,
        files: 1,
        fields: 1,
        fieldSize: 16,
        parts: 3,
      },
    }),
  )
  upload(
    @CurrentUser() user: Identity,
    @Body() _dto: UploadConsentDto,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.service.upload(user.id, file);
  }
  @Get() list(@CurrentUser() user: Identity) {
    return this.service.list(user.id);
  }
  @Get(':id') read(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.service.read(user.id, id);
  }
  @Delete(':id')
  @HttpCode(202)
  delete(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.lifecycle.deleteOwned(user.id, id);
  }
}
