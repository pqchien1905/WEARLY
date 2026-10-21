import {
  Body,
  Controller,
  Get,
  Header,
  Headers,
  Param,
  ParseUUIDPipe,
  Post,
  Res,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiBearerAuth,
  ApiBody,
  ApiConsumes,
  ApiHeader,
  ApiTags,
} from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Transform } from 'class-transformer';
import { IsString, MaxLength, ValidateIf } from 'class-validator';
import { Response } from 'express';
import {
  Admin,
  CurrentUser,
  Identity,
  Public,
} from '../../common/decorators/auth';
import { MAX_IMAGE_BYTES } from '../../integrations/storage/image-policy';
import { CatalogMediaService } from './catalog-media.service';
class CatalogUploadDto {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(200)
  alt!: string;
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(60)
  color?: string;
}
@ApiTags('catalog-media')
@Controller()
export class CatalogMediaController {
  constructor(private readonly service: CatalogMediaService) {}
  @Admin('catalog.write')
  @ApiBearerAuth()
  @Post('admin/products/:id/images')
  @Throttle({ default: { limit: 30, ttl: 60000 } })
  @ApiConsumes('multipart/form-data')
  @ApiHeader({ name: 'Idempotency-Key', required: true })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['file', 'alt'],
      properties: {
        file: { type: 'string', format: 'binary' },
        alt: { type: 'string', maxLength: 200 },
        color: { type: 'string', maxLength: 60 },
      },
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      limits: {
        fileSize: MAX_IMAGE_BYTES,
        files: 1,
        fields: 2,
        fieldSize: 1000,
        parts: 4,
      },
    }),
  )
  upload(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Headers('idempotency-key') key: string | undefined,
    @Body() metadata: CatalogUploadDto,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.service.upload(user.id, id, key, metadata, file);
  }
  @Public()
  @Get('catalog/images/:id')
  @Header('Cross-Origin-Resource-Policy', 'cross-origin')
  @Header('X-Content-Type-Options', 'nosniff')
  async read(
    @Param('id', ParseUUIDPipe) id: string,
    @Res() response: Response,
  ) {
    const image = await this.service.read(id);
    response.setHeader('Cache-Control', 'public, max-age=3600');
    response.type(image.mimeType).send(image.bytes);
  }
}
