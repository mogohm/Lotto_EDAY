import { BadRequestException, Body, Controller, ForbiddenException, Get, HttpCode, Injectable, Patch, Post, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Throttle } from '@nestjs/throttler';
import { Role, User, UserStatus } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { IsEmail, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { AuthUser, ClientIp, CurrentUser, jwtSecret, Public } from './common/auth';
import { Database, writeAudit } from './common/database';
import { ROLE_PERMISSIONS } from './common/permissions';
import { SettingsService } from './common/settings.service';

/** Per-IP requests/minute for register & password change (login gets 2x). */
const AUTH_LIMIT = Number(process.env.AUTH_RATE_LIMIT || 5);
const DUMMY_HASH = bcrypt.hashSync('timing-equaliser-not-a-password', 10);
export const PASSWORD_RULE = /^(?=.*[A-Za-z])(?=.*\d).{8,72}$/;

class LoginDto {
  @IsEmail() email!: string;
  @IsString() @MinLength(1) @MaxLength(72) password!: string;
}
class RegisterDto {
  @IsEmail() email!: string;
  @Matches(PASSWORD_RULE, { message: 'รหัสผ่านต้องยาว 8 ตัวขึ้นไป มีทั้งตัวอักษรและตัวเลข' }) password!: string;
  @IsString() @MinLength(2) @MaxLength(80) displayName!: string;
  @IsOptional() @Matches(/^0\d{8,9}$/, { message: 'เบอร์โทรไม่ถูกต้อง' }) phone?: string;
}
class ProfileDto {
  @IsOptional() @IsString() @MinLength(2) @MaxLength(80) displayName?: string;
  @IsOptional() @Matches(/^0\d{8,9}$/, { message: 'เบอร์โทรไม่ถูกต้อง' }) phone?: string;
}
class ChangePasswordDto {
  @IsString() currentPassword!: string;
  @Matches(PASSWORD_RULE, { message: 'รหัสผ่านต้องยาว 8 ตัวขึ้นไป มีทั้งตัวอักษรและตัวเลข' }) newPassword!: string;
}

export function publicUser(u: User) {
  return {
    id: u.id, email: u.email, phone: u.phone, displayName: u.displayName, role: u.role, status: u.status,
    kycStatus: u.kycStatus, demoBalance: u.demoBalance, lastLoginAt: u.lastLoginAt, createdAt: u.createdAt,
    permissions: ROLE_PERMISSIONS[u.role],
  };
}

@Injectable()
export class AuthService {
  constructor(private readonly db: Database, private readonly jwt: JwtService, private readonly settings: SettingsService) {}

  sign(u: User) {
    return this.jwt.signAsync({ sub: u.id, tv: u.tokenVersion, role: u.role }, { secret: jwtSecret(), expiresIn: '8h' });
  }

  async login(email: string, password: string, ip?: string) {
    const user = await this.db.user.findUnique({ where: { email: email.toLowerCase().trim() } });
    // Constant-ish work even when the user doesn't exist.
    const ok = await bcrypt.compare(password, user?.passwordHash ?? DUMMY_HASH);
    if (!user || !ok) throw new UnauthorizedException('อีเมลหรือรหัสผ่านไม่ถูกต้อง');
    if (user.status !== UserStatus.ACTIVE) throw new ForbiddenException('บัญชีนี้ถูกระงับการใช้งาน');
    const updated = await this.db.$transaction(async (tx) => {
      const u = await tx.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
      await writeAudit(tx, { actor: u.email, actorId: u.id, action: 'LOGIN', entityType: 'user', entityId: u.id, ip });
      return u;
    });
    return { accessToken: await this.sign(updated), user: publicUser(updated) };
  }

  async register(dto: RegisterDto, ip?: string) {
    if (!(await this.settings.get<boolean>('registrationOpen'))) throw new ForbiddenException('ปิดรับสมัครสมาชิกชั่วคราว');
    const email = dto.email.toLowerCase().trim();
    if (await this.db.user.findUnique({ where: { email } })) throw new BadRequestException('อีเมลนี้ถูกใช้แล้ว');
    const user = await this.db.$transaction(async (tx) => {
      const u = await tx.user.create({
        data: { email, displayName: dto.displayName.trim(), phone: dto.phone, passwordHash: await bcrypt.hash(dto.password, 10), role: Role.USER },
      });
      await writeAudit(tx, { actor: u.email, actorId: u.id, action: 'REGISTER', entityType: 'user', entityId: u.id, ip });
      await tx.notification.create({ data: { userId: u.id, title: 'ยินดีต้อนรับสู่ LOTTO DAY', body: 'บัญชีของคุณเป็นบัญชีสาธิต ธุรกรรมทั้งหมดเป็นการจำลอง ไม่มีการชำระเงินจริง' } });
      return u;
    });
    return { accessToken: await this.sign(user), user: publicUser(user) };
  }
}

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService, private readonly db: Database) {}

  @Public() @Post('login') @HttpCode(200) @Throttle({ default: { limit: AUTH_LIMIT * 2, ttl: 60_000 } })
  login(@Body() dto: LoginDto, @ClientIp() ip: string) { return this.auth.login(dto.email, dto.password, ip); }

  @Public() @Post('register') @Throttle({ default: { limit: AUTH_LIMIT, ttl: 60_000 } })
  register(@Body() dto: RegisterDto, @ClientIp() ip: string) { return this.auth.register(dto, ip); }

  @Get('me')
  async me(@CurrentUser() user: AuthUser) { return publicUser(await this.db.user.findUniqueOrThrow({ where: { id: user.id } })); }

  @Patch('me')
  async updateProfile(@CurrentUser() user: AuthUser, @Body() dto: ProfileDto, @ClientIp() ip: string) {
    return this.db.$transaction(async (tx) => {
      const before = await tx.user.findUniqueOrThrow({ where: { id: user.id } });
      const u = await tx.user.update({ where: { id: user.id }, data: { displayName: dto.displayName?.trim(), phone: dto.phone } });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action: 'UPDATE_PROFILE', entityType: 'user', entityId: user.id, ip,
        before: { displayName: before.displayName, phone: before.phone }, after: { displayName: u.displayName, phone: u.phone } });
      return publicUser(u);
    });
  }

  @Post('change-password') @HttpCode(200) @Throttle({ default: { limit: AUTH_LIMIT, ttl: 60_000 } })
  async changePassword(@CurrentUser() user: AuthUser, @Body() dto: ChangePasswordDto, @ClientIp() ip: string) {
    const u = await this.db.user.findUniqueOrThrow({ where: { id: user.id } });
    if (!(await bcrypt.compare(dto.currentPassword, u.passwordHash))) throw new BadRequestException('รหัสผ่านปัจจุบันไม่ถูกต้อง');
    const updated = await this.db.$transaction(async (tx) => {
      const x = await tx.user.update({ where: { id: u.id }, data: { passwordHash: await bcrypt.hash(dto.newPassword, 10), tokenVersion: { increment: 1 } } });
      await writeAudit(tx, { actor: u.email, actorId: u.id, action: 'CHANGE_PASSWORD', entityType: 'user', entityId: u.id, ip });
      return x;
    });
    // Old tokens are revoked via tokenVersion; return a fresh one.
    return { accessToken: await this.auth.sign(updated), user: publicUser(updated) };
  }

  @Post('logout-all') @HttpCode(200)
  async logoutAll(@CurrentUser() user: AuthUser) {
    await this.db.user.update({ where: { id: user.id }, data: { tokenVersion: { increment: 1 } } });
    return { ok: true };
  }
}
