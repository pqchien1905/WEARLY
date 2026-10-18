import { Module } from '@nestjs/common';
import {
  CustomerReviewsController,
  ReviewsController,
} from './reviews.controller';
import { ReviewsService } from './reviews.service';
@Module({
  controllers: [ReviewsController, CustomerReviewsController],
  providers: [ReviewsService],
})
export class ReviewsModule {}
