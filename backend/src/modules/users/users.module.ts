import { Module } from '@nestjs/common';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';
import { StyleService } from './style.service';
@Module({
  controllers: [UsersController],
  providers: [UsersService, StyleService],
})
export class UsersModule {}
