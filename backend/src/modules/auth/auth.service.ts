import {
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { createHash, randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import { PrismaService } from '../../database/prisma.service';
import { Prisma, User } from '../../generated/prisma/client';
import { RegisterDto, LoginDto } from './dto/auth.dto';
import { transaction, lockUser } from '../../common/transaction';
import { isStaff } from '../../common/permissions';
export const publicUser = (u: User) => ({
  id: u.id,
  email: u.email,
  name: u.name,
  phone: u.phone,
  role: u.role,
  createdAt: u.createdAt,
});
const digest = (s: string) => createHash('sha256').update(s).digest('hex');
@Injectable()
export class AuthService {
  constructor(
    private readonly db: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}
  async register(dto: RegisterDto) {
    const passwordHash = await argon2.hash(dto.password, {
      type: argon2.argon2id,
      memoryCost: 19456,
      timeCost: 2,
      parallelism: 1,
    });
    return this.db.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: { email: dto.email, name: dto.name, passwordHash },
      });
      return this.issue(tx, user, randomUUID());
    });
  }
  async login(dto: LoginDto, adminOnly = false) {
    const user = await this.db.user.findUnique({ where: { email: dto.email } });
    if (
      !user ||
      !user.active ||
      !(await argon2.verify(user.passwordHash, dto.password))
    )
      throw new UnauthorizedException('Invalid email or password');
    if (adminOnly && !isStaff(user.role))
      throw new ForbiddenException('Administrator access is required');
    return transaction(this.db, async (tx) => {
      await lockUser(tx, user.id);
      const current = await tx.user.findUnique({ where: { id: user.id } });
      if (!current?.active || current.passwordHash !== user.passwordHash)
        throw new UnauthorizedException('Invalid email or password');
      if (adminOnly && !isStaff(current.role))
        throw new ForbiddenException('Administrator access is required');
      return this.issue(tx, current, randomUUID());
    });
  }
  private async issue(
    tx: Prisma.TransactionClient,
    user: User,
    familyId: string,
  ) {
    const id = randomUUID();
    const refreshSeconds = this.config.getOrThrow<number>(
      'JWT_REFRESH_EXPIRES_IN',
    );
    const refreshToken = await this.jwt.signAsync(
      { sub: user.id, sid: id, typ: 'refresh' },
      {
        secret: this.config.getOrThrow<string>('JWT_REFRESH_SECRET'),
        expiresIn: refreshSeconds,
        algorithm: 'HS256',
        issuer: 'wearly',
        audience: 'wearly-refresh',
      },
    );
    await tx.refreshToken.create({
      data: {
        id,
        userId: user.id,
        familyId,
        tokenHash: digest(refreshToken),
        expiresAt: new Date(Date.now() + refreshSeconds * 1000),
      },
    });
    const expiresIn = this.config.getOrThrow<number>('JWT_ACCESS_EXPIRES_IN');
    const accessToken = await this.jwt.signAsync(
      { sub: user.id, sid: id, typ: 'access' },
      {
        secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
        expiresIn,
        algorithm: 'HS256',
        issuer: 'wearly',
        audience: 'wearly-api',
      },
    );
    return { user: publicUser(user), accessToken, refreshToken, expiresIn };
  }
  async refresh(token: string) {
    let claims: { sub: string; sid: string; typ: string };
    try {
      claims = await this.jwt.verifyAsync(token, {
        secret: this.config.getOrThrow<string>('JWT_REFRESH_SECRET'),
        algorithms: ['HS256'],
        issuer: 'wearly',
        audience: 'wearly-refresh',
      });
    } catch {
      throw new UnauthorizedException();
    }
    if (claims.typ !== 'refresh') throw new UnauthorizedException();
    const result = await transaction(this.db, async (tx) => {
      await lockUser(tx, claims.sub);
      const session = await tx.refreshToken.findUnique({
        where: { tokenHash: digest(token) },
        include: { user: true },
      });
      if (
        !session ||
        session.id !== claims.sid ||
        session.userId !== claims.sub ||
        !session.user.active
      )
        return null;
      if (session.revokedAt || session.expiresAt <= new Date()) {
        await tx.refreshToken.updateMany({
          where: {
            userId: session.userId,
            familyId: session.familyId,
            revokedAt: null,
          },
          data: { revokedAt: new Date() },
        });
        return null;
      }
      await tx.refreshToken.update({
        where: { id: session.id },
        data: { revokedAt: new Date() },
      });
      return this.issue(tx, session.user, session.familyId);
    });
    if (!result) throw new UnauthorizedException();
    return result;
  }
  async logout(userId: string, sessionId: string) {
    await transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const session = await tx.refreshToken.findFirst({
        where: { id: sessionId, userId },
      });
      if (session)
        await tx.refreshToken.updateMany({
          where: { userId, familyId: session.familyId, revokedAt: null },
          data: { revokedAt: new Date() },
        });
    });
    return { loggedOut: true };
  }
  async me(id: string) {
    return publicUser(await this.db.user.findUniqueOrThrow({ where: { id } }));
  }
}
