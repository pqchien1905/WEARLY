import {
  createParamDecorator,
  ExecutionContext,
  SetMetadata,
} from '@nestjs/common';
import { Request } from 'express';
export type Identity = {
  id: string;
  role: 'CUSTOMER' | 'ADMIN';
  sessionId: string;
};
export type AuthRequest = Request & { user: Identity };
export const Public = () => SetMetadata('public', true);
export const Admin = () => SetMetadata('admin', true);
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): Identity =>
    ctx.switchToHttp().getRequest<AuthRequest>().user,
);
