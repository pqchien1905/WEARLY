import {
  createParamDecorator,
  ExecutionContext,
  SetMetadata,
} from '@nestjs/common';
import { Request } from 'express';
import { Role } from '../../generated/prisma/client';
import { Capability } from '../permissions';
export type Identity = {
  id: string;
  role: Role;
  sessionId: string;
};
export type AuthRequest = Request & { user: Identity };
export const Public = () => SetMetadata('public', true);
export const Admin = (capability: Capability = 'staff.manage') =>
  SetMetadata('admin', capability);
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): Identity =>
    ctx.switchToHttp().getRequest<AuthRequest>().user,
);
