import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../database/prisma.service';
import { AuthRequest } from '../decorators/auth';
import { can, Capability } from '../permissions';
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly db: PrismaService,
  ) {}
  async canActivate(context: ExecutionContext) {
    if (
      this.reflector.getAllAndOverride<boolean>('public', [
        context.getHandler(),
        context.getClass(),
      ])
    )
      return true;
    const req = context.switchToHttp().getRequest<AuthRequest>();
    const [scheme, token] = (req.headers.authorization ?? '').split(' ');
    if (scheme !== 'Bearer' || !token) throw new UnauthorizedException();
    let payload: { sub: string; sid: string; typ: string };
    try {
      payload = await this.jwt.verifyAsync(token, {
        secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
        algorithms: ['HS256'],
        issuer: 'wearly',
        audience: 'wearly-api',
      });
    } catch {
      throw new UnauthorizedException();
    }
    if (payload.typ !== 'access' || !payload.sub || !payload.sid)
      throw new UnauthorizedException();
    const session = await this.db.refreshToken.findFirst({
      where: {
        id: payload.sid,
        userId: payload.sub,
        revokedAt: null,
        expiresAt: { gt: new Date() },
        user: { active: true },
      },
      include: { user: true },
    });
    if (!session) throw new UnauthorizedException();
    req.user = {
      id: session.userId,
      role: session.user.role,
      sessionId: session.id,
    };
    const capability = this.reflector.getAllAndOverride<Capability>('admin', [
      context.getHandler(),
      context.getClass(),
    ]);
    if (capability && !can(session.user.role, capability))
      throw new ForbiddenException();
    return true;
  }
}
