import { Module } from '@nestjs/common';
import {
  AdminReviewsController,
  CustomerReviewsController,
  ReviewsController,
} from './reviews.controller';
import { ReviewsService } from './reviews.service';
@Module({
  controllers: [
    ReviewsController,
    CustomerReviewsController,
    AdminReviewsController,
  ],
  providers: [ReviewsService],
})
export class ReviewsModule {}
