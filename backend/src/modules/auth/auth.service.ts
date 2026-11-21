import {
  ConflictException,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import { PrismaService } from '../../database/prisma.service';
import { Prisma, User } from '../../generated/prisma/client';
import { RegisterDto, LoginDto, AdminLoginDto } from './dto/auth.dto';
import { transaction, lockUser } from '../../common/transaction';
import { isStaff } from '../../common/permissions';
export const publicUser = (u: User) => ({
  id: u.id,
  email: u.email,
  username: u.username,
  name: u.name,
  phone: u.phone,
  role: u.role,
  createdAt: u.createdAt,
});
const digest = (s: string) => createHash('sha256').update(s).digest('hex');
export type BrowserScope = 'customer' | 'admin';
export const browserLifetime = (scope: BrowserScope) =>
  scope === 'admin' ? 28800 : 604800;
@Injectable()
export class AuthService {
  constructor(
    private readonly db: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}
  async register(dto: RegisterDto, scope?: BrowserScope, previous?: string) {
    const passwordHash = await argon2.hash(dto.password, {
      type: argon2.argon2id,
      memoryCost: 19456,
      timeCost: 2,
      parallelism: 1,
    });
    try {
      return await this.db.$transaction(async (tx) => {
        const user = await tx.user.create({
          data: { email: dto.email, name: dto.name, passwordHash },
        });
        return this.issue(tx, user, randomUUID(), scope, previous);
      });
    } catch (error) {
      // Check after rollback so concurrent signups are covered without treating
      // unrelated unique constraints (such as session tokens) as email conflicts.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002' &&
        (await this.db.user.findUnique({
          where: { email: dto.email },
          select: { id: true },
        }))
      ) {
        throw new ConflictException({
          code: 'EMAIL_ALREADY_EXISTS',
          message: 'An account with this email already exists',
        });
      }
      throw error;
    }
  }
  async login(
    dto: LoginDto | AdminLoginDto,
    adminOnly = false,
    scope?: BrowserScope,
    previous?: string,
  ) {
    if (
      (adminOnly && !('username' in dto)) ||
      (!adminOnly && !('email' in dto))
    )
      throw new UnauthorizedException('Invalid credentials');
    const user = await this.db.user.findUnique({
      where:
        'username' in dto ? { username: dto.username } : { email: dto.email },
    });
    if (
      !user ||
      !user.active ||
      !(await argon2.verify(user.passwordHash, dto.password))
    )
      throw new UnauthorizedException('Invalid credentials');
    if (adminOnly && !isStaff(user.role))
      throw new ForbiddenException('Administrator access is required');
    if (!adminOnly && user.role !== 'CUSTOMER')
      throw new ForbiddenException({
        code: 'CUSTOMER_ACCOUNT_REQUIRED',
        message: 'Use a separate customer account or sign in to administration',
      });
    return transaction(this.db, async (tx) => {
      await lockUser(tx, user.id);
      const current = await tx.user.findUnique({ where: { id: user.id } });
      if (!current?.active || current.passwordHash !== user.passwordHash)
        throw new UnauthorizedException('Invalid credentials');
      if (adminOnly && !isStaff(current.role))
        throw new ForbiddenException('Administrator access is required');
      if (!adminOnly && current.role !== 'CUSTOMER')
        throw new ForbiddenException({
          code: 'CUSTOMER_ACCOUNT_REQUIRED',
          message:
            'Use a separate customer account or sign in to administration',
        });
      return this.issue(tx, current, randomUUID(), scope, previous);
    });
  }
  private async issue(
    tx: Prisma.TransactionClient,
    user: User,
    familyId: string,
    scope?: BrowserScope,
    previous?: string,
  ) {
    const id = randomUUID();
    const refreshSeconds = scope
      ? browserLifetime(scope)
      : this.config.getOrThrow<number>('JWT_REFRESH_EXPIRES_IN');
    const refreshToken = scope
      ? randomBytes(32).toString('base64url')
      : await this.jwt.signAsync(
          { sub: user.id, sid: id, typ: 'refresh' },
          {
            secret: this.config.getOrThrow<string>('JWT_REFRESH_SECRET'),
            expiresIn: refreshSeconds,
            algorithm: 'HS256',
            issuer: 'wearly',
            audience: 'wearly-refresh',
          },
        );
    if (scope && previous) {
      await tx.refreshToken.updateMany({
        where: {
          tokenHash: digest(previous),
          browserScope: scope,
          revokedAt: null,
        },
        data: { revokedAt: new Date() },
      });
    }
    await tx.refreshToken.create({
      data: {
        id,
        userId: user.id,
        familyId,
        browserScope: scope,
        tokenHash: digest(refreshToken),
        expiresAt: new Date(Date.now() + refreshSeconds * 1000),
      },
    });
    return { ...(await this.access(user, id)), refreshToken };
  }
  private async access(user: User, id: string) {
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
    return { user: publicUser(user), accessToken, expiresIn };
  }
  async resumeBrowser(token: string | undefined, scope: BrowserScope) {
    if (!token || !/^[A-Za-z0-9_-]{43}$/.test(token))
      throw new UnauthorizedException();
    const candidate = await this.db.refreshToken.findUnique({
      where: { tokenHash: digest(token) },
    });
    if (!candidate || candidate.browserScope !== scope)
      throw new UnauthorizedException();
    return transaction(this.db, async (tx) => {
      await lockUser(tx, candidate.userId);
      const session = await tx.refreshToken.findUnique({
        where: { id: candidate.id },
        include: { user: true },
      });
      if (
        !session ||
        session.revokedAt ||
        session.expiresAt <= new Date() ||
        !session.user.active ||
        (scope === 'admin' && !isStaff(session.user.role)) ||
        (scope === 'customer' && session.user.role !== 'CUSTOMER')
      )
        throw new UnauthorizedException();
      return this.access(session.user, session.id);
    });
  }
  async logoutBrowser(token: string | undefined, scope: BrowserScope) {
    if (token) {
      const session = await this.db.refreshToken.findUnique({
        where: { tokenHash: digest(token) },
      });
      if (session?.browserScope === scope)
        await this.logout(session.userId, session.id);
    }
    return { loggedOut: true };
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
