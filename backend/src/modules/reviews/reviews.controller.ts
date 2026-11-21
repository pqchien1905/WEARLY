import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  Admin,
  CurrentUser,
  Identity,
  Public,
} from '../../common/decorators/auth';
import { ReviewsService } from './reviews.service';
import {
  AdminReviewQueryDto,
  CreateReviewDto,
  OwnedReviewPageDto,
  ReviewPageDto,
  ReviewVersionDto,
  ReviewVisibilityDto,
  UpdateReviewDto,
} from './review.dto';

@ApiTags('reviews')
@ApiBearerAuth()
@Controller('users/me/reviews')
export class CustomerReviewsController {
  constructor(private readonly service: ReviewsService) {}
  @Get() history(
    @CurrentUser() user: Identity,
    @Query() q: OwnedReviewPageDto,
  ) {
    return this.service.history(user.id, q);
  }
}

@ApiTags('reviews')
@Controller('products/:productId/reviews')
export class ReviewsController {
  constructor(private readonly service: ReviewsService) {}
  @Public() @Get() list(
    @Param('productId', ParseUUIDPipe) productId: string,
    @Query() q: ReviewPageDto,
  ) {
    return this.service.list(productId, q);
  }
  @ApiBearerAuth() @Get('me') mine(
    @CurrentUser() user: Identity,
    @Param('productId', ParseUUIDPipe) productId: string,
  ) {
    return this.service.mine(user.id, productId);
  }
  @ApiBearerAuth() @Post() create(
    @CurrentUser() user: Identity,
    @Param('productId', ParseUUIDPipe) productId: string,
    @Body() dto: CreateReviewDto,
  ) {
    return this.service.save(user.id, productId, dto);
  }
  @ApiBearerAuth() @Patch('me') update(
    @CurrentUser() user: Identity,
    @Param('productId', ParseUUIDPipe) productId: string,
    @Body() dto: UpdateReviewDto,
  ) {
    return this.service.save(user.id, productId, dto);
  }
  @ApiBearerAuth() @Delete('me') remove(
    @CurrentUser() user: Identity,
    @Param('productId', ParseUUIDPipe) productId: string,
    @Body() dto: ReviewVersionDto,
  ) {
    return this.service.remove(user.id, productId, dto);
  }
}

@Admin('content.manage')
@ApiBearerAuth()
@ApiTags('admin')
@Controller('admin/reviews')
export class AdminReviewsController {
  constructor(private readonly service: ReviewsService) {}
  @Get() list(@Query() q: AdminReviewQueryDto) {
    return this.service.adminList(q);
  }
  @Patch(':id/visibility') visibility(
    @CurrentUser() user: Identity,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReviewVisibilityDto,
  ) {
    return this.service.setVisibility(user.id, id, dto);
  }
}
