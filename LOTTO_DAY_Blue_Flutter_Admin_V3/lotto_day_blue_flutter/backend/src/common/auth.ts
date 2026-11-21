import {
  CanActivate, createParamDecorator, ExecutionContext, ForbiddenException, Injectable, SetMetadata, UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Role, UserStatus } from '@prisma/client';
import { Database } from './database';
import { hasPermission, Permission } from './permissions';

export interface AuthUser { id: string; email: string; role: Role; displayName: string }

export const PUBLIC_KEY = 'isPublic';
export const PERMS_KEY = 'perms';
/** Route needs no token. */
export const Public = () => SetMetadata(PUBLIC_KEY, true);
/** Route requires ALL listed permissions. */
export const RequirePerms = (...perms: Permission[]) => SetMetadata(PERMS_KEY, perms);

export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthUser => ctx.switchToHttp().getRequest().user);
export const ClientIp = createParamDecorator((_: unknown, ctx: ExecutionContext): string => {
  const req = ctx.switchToHttp().getRequest();
  return (req.headers['fly-client-ip'] as string) || req.ip || '';
});

export function jwtSecret() {
  const s = process.env.JWT_SECRET;
  if (s && s.length >= 32) return s;
  if (process.env.NODE_ENV === 'production') throw new Error('JWT_SECRET (>=32 chars) must be set in production');
  return 'dev-only-insecure-jwt-secret-change-me-0123456789';
}

/** Global guard: Bearer JWT (stateless) + token version revocation + per-route permissions. */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, private readonly jwt: JwtService, private readonly db: Database) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const handlers = [ctx.getHandler(), ctx.getClass()];
    const isPublic = this.reflector.getAllAndOverride<boolean>(PUBLIC_KEY, handlers);
    const req = ctx.switchToHttp().getRequest();
    const header: string | undefined = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.substring(7) : undefined;

    if (!token) {
      if (isPublic) return true;
      throw new UnauthorizedException('กรุณาเข้าสู่ระบบ');
    }
    let payload: { sub: string; tv: number };
    try {
      payload = await this.jwt.verifyAsync(token, { secret: jwtSecret() });
    } catch {
      if (isPublic) return true;
      throw new UnauthorizedException('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
    }
    const user = await this.db.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.tokenVersion !== payload.tv || user.status !== UserStatus.ACTIVE) {
      if (isPublic) return true;
      throw new UnauthorizedException('บัญชีถูกระงับหรือเซสชันถูกยกเลิก');
    }
    req.user = { id: user.id, email: user.email, role: user.role, displayName: user.displayName } satisfies AuthUser;

    const perms = this.reflector.getAllAndOverride<Permission[]>(PERMS_KEY, handlers) ?? [];
    for (const p of perms) if (!hasPermission(user.role, p)) throw new ForbiddenException(`ไม่มีสิทธิ์: ${p}`);
    return true;
  }
}
