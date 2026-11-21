import { Controller, Get, Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { ServeStaticModule } from '@nestjs/serve-static';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { AdminController, AdminService } from './admin';
import { AuthController, AuthService } from './auth.controller';
import { AuthGuard, Public } from './common/auth';
import { Database } from './common/database';
import { AllExceptionsFilter } from './common/errors';
import { SettingsService } from './common/settings.service';
import { CommerceController, CommerceService } from './commerce';
import { LotteryAdminController, LotteryController } from './lottery.controller';
import { LotteryService } from './lottery.service';

export { Database } from './common/database';

@Controller()
class MetaController {
  constructor(private readonly db: Database, private readonly settings: SettingsService) {}
  @Public() @Get('health') async health() {
    await this.db.$queryRaw`SELECT 1`;
    return { ok: true, service: 'lotto-day-api', time: new Date().toISOString() };
  }
  @Public() @Get('config') config() { return this.settings.publicConfig(); }
}

/** Flutter web build is served from WEB_DIR (default: ../build/web relative to backend, or ./public in Docker). */
export function webDir() {
  const candidates = [process.env.WEB_DIR, join(__dirname, '..', 'public'), join(__dirname, '..', '..', 'public'), join(__dirname, '..', '..', 'build', 'web'), join(__dirname, '..', '..', '..', 'build', 'web')];
  return candidates.find((c) => c && existsSync(join(c, 'index.html')));
}

const staticDir = process.env.NODE_ENV === 'test' ? undefined : webDir();

@Module({
  imports: [
    JwtModule.register({}),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: Number(process.env.RATE_LIMIT_PER_MINUTE || 300) }]),
    ...(staticDir ? [ServeStaticModule.forRoot({ rootPath: staticDir, exclude: ['/api/(.*)'] })] : []),
  ],
  controllers: [MetaController, AuthController, LotteryController, LotteryAdminController, CommerceController, AdminController],
  providers: [
    Database, SettingsService, AuthService, LotteryService, CommerceService, AdminService,
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
  ],
})
export class AppModule {}
