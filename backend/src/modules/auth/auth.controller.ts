import { Body, Controller, Get, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser, Identity, Public } from '../../common/decorators/auth';
import { AuthService } from './auth.service';
import { LoginDto, RegisterDto, RefreshDto, AdminLoginDto } from './dto/auth.dto';
@ApiTags('auth')
@Controller('auth')
@Throttle({ default: { limit: 30, ttl: 60000 } })
export class AuthController {
  constructor(private readonly service: AuthService) {}
  @Public() @Post('register') register(@Body() dto: RegisterDto) {
    return this.service.register(dto);
  }
  @Public() @Post('login') login(@Body() dto: LoginDto) {
    return this.service.login(dto);
  }
  @Public() @Post('admin/login') adminLogin(@Body() dto: AdminLoginDto) {
    return this.service.login(dto, true);
  }
  @Public() @Post('refresh') refresh(@Body() dto: RefreshDto) {
    return this.service.refresh(dto.refreshToken);
  }
  @ApiBearerAuth() @Post('logout') logout(@CurrentUser() u: Identity) {
    return this.service.logout(u.id, u.sessionId);
  }
  @ApiBearerAuth() @Get('me') me(@CurrentUser() u: Identity) {
    return this.service.me(u.id);
  }
}
