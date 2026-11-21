import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { ApiBearerAuth } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import {
  CurrentUser,
  Identity,
  Public,
} from '../../common/decorators/auth';
import {
  ChangePasswordDto,
  ForgotPasswordDto,
  ResetPasswordDto,
  VerifyResetCodeDto,
} from './recovery.dto';
import { RecoveryService } from './recovery.service';
@Controller('auth')
export class RecoveryController {
  constructor(private readonly recovery: RecoveryService) {}
  @Public()
  @Post('forgot-password')
  @HttpCode(202)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  request(@Body() dto: ForgotPasswordDto) {
    return this.recovery.request(dto.email);
  }
  @Public()
  @Post('verify-reset-code')
  @HttpCode(200)
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  verify(@Body() dto: VerifyResetCodeDto) {
    return this.recovery.verifyCode(dto.email, dto.code);
  }
  @Public()
  @Post('reset-password')
  @HttpCode(200)
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  reset(@Body() dto: ResetPasswordDto) {
    return this.recovery.reset(dto.token, dto.password);
  }
  /** Customers and staff change their own password while signed in. */
  @ApiBearerAuth()
  @Post('change-password')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  change(@CurrentUser() u: Identity, @Body() dto: ChangePasswordDto) {
    return this.recovery.changePassword(
      u.id,
      u.sessionId,
      dto.currentPassword,
      dto.newPassword,
    );
  }
}
