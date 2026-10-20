import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../../common/decorators/auth';
import { ForgotPasswordDto, ResetPasswordDto } from './recovery.dto';
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
  @Post('reset-password')
  @HttpCode(200)
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  reset(@Body() dto: ResetPasswordDto) {
    return this.recovery.reset(dto.token, dto.password);
  }
}
