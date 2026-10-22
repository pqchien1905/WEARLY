import {
  Body,
  CanActivate,
  Controller,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  Post,
  Req,
  Res,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Throttle } from '@nestjs/throttler';
import { Request, Response } from 'express';
import { Public } from '../../common/decorators/auth';
import { AuthService, BrowserScope, browserLifetime } from './auth.service';
import { LoginDto, RegisterDto, AdminLoginDto } from './dto/auth.dto';

const loopback = (host: string) =>
  ['localhost', '127.0.0.1', '[::1]', '::1'].includes(host);
const cookieName = (scope: BrowserScope) => `wearly_${scope}_session`;
const cookiePath = (scope: BrowserScope) => `/api/v1/auth/browser/${scope}`;
function readCookie(req: Request, scope: BrowserScope) {
  const values = (req.headers.cookie ?? '')
    .split(';')
    .map((v) => v.trim())
    .filter((v) => v.startsWith(cookieName(scope) + '='));
  if (!values.length) return undefined;
  const token = values[0].slice(cookieName(scope).length + 1);
  if (values.length !== 1 || !/^[A-Za-z0-9_-]{43}$/.test(token))
    throw new UnauthorizedException();
  return token;
}

@Injectable()
export class BrowserOriginGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}
  canActivate(context: ExecutionContext) {
    const req = context.switchToHttp().getRequest<Request>();
    const origin = req.get('Origin');
    const allowed = this.config
      .getOrThrow<string>('CORS_ORIGINS')
      .split(',')
      .map((v) => v.trim());
    if (
      !origin ||
      !allowed.includes(origin) ||
      req.get('X-Wearly-Browser') !== '1'
    )
      throw new ForbiddenException();
    const source = new URL(origin);
    if (
      this.config.get('NODE_ENV') === 'production' &&
      (source.protocol !== 'https:' || !req.secure)
    )
      throw new ForbiddenException();
    if (source.protocol !== 'https:' && !loopback(source.hostname))
      throw new ForbiddenException();
    if (!req.secure && !loopback(req.hostname)) throw new ForbiddenException();
    return true;
  }
}

@Public()
@UseGuards(BrowserOriginGuard)
@Throttle({ default: { limit: 30, ttl: 60000 } })
@Controller('auth/browser')
export class BrowserAuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly config: ConfigService,
  ) {}
  private options(req: Request, scope: BrowserScope) {
    return {
      httpOnly: true,
      sameSite: 'strict' as const,
      path: cookiePath(scope),
      secure: req.secure || this.config.get('NODE_ENV') === 'production',
    };
  }
  private issued(
    req: Request,
    res: Response,
    scope: BrowserScope,
    result: Awaited<ReturnType<AuthService['login']>>,
  ) {
    res.setHeader('Cache-Control', 'no-store');
    res.cookie(cookieName(scope), result.refreshToken, {
      ...this.options(req, scope),
      maxAge: browserLifetime(scope) * 1000,
    });
    return {
      user: result.user,
      accessToken: result.accessToken,
      expiresIn: result.expiresIn,
    };
  }
  @Post('customer/register')
  async register(
    @Body() dto: RegisterDto,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    return this.issued(
      req,
      res,
      'customer',
      await this.auth.register(dto, 'customer', readCookie(req, 'customer')),
    );
  }
  @Post('customer/login')
  async customerLogin(
    @Body() dto: LoginDto,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    return this.issued(
      req,
      res,
      'customer',
      await this.auth.login(
        dto,
        false,
        'customer',
        readCookie(req, 'customer'),
      ),
    );
  }
  @Post('admin/login')
  async adminLogin(
    @Body() dto: AdminLoginDto,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    return this.issued(
      req,
      res,
      'admin',
      await this.auth.login(dto, true, 'admin', readCookie(req, 'admin')),
    );
  }
  @Post('customer/refresh')
  customerRefresh(
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    res.setHeader('Cache-Control', 'no-store');
    return this.auth.resumeBrowser(readCookie(req, 'customer'), 'customer');
  }
  @Post('admin/refresh')
  adminRefresh(@Req() req: Request, @Res({ passthrough: true }) res: Response) {
    res.setHeader('Cache-Control', 'no-store');
    return this.auth.resumeBrowser(readCookie(req, 'admin'), 'admin');
  }
  private async logout(req: Request, res: Response, scope: BrowserScope) {
    const result = await this.auth.logoutBrowser(readCookie(req, scope), scope);
    res.setHeader('Cache-Control', 'no-store');
    res.clearCookie(cookieName(scope), this.options(req, scope));
    return result;
  }
  @Post('customer/logout')
  customerLogout(
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    return this.logout(req, res, 'customer');
  }
  @Post('admin/logout')
  adminLogout(@Req() req: Request, @Res({ passthrough: true }) res: Response) {
    return this.logout(req, res, 'admin');
  }
}
