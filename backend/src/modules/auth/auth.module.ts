import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { RecoveryModule } from '../recovery/recovery.module';
import { RecoveryController } from '../recovery/recovery.controller';
import {
  BrowserAuthController,
  BrowserOriginGuard,
} from './browser-auth.controller';
@Module({
  imports: [RecoveryModule],
  controllers: [AuthController, RecoveryController, BrowserAuthController],
  providers: [AuthService, BrowserOriginGuard],
})
export class AuthModule {}
