import { BadRequestException, ForbiddenException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Database, writeAudit } from './database';
import { AuthUser } from './auth';

/**
 * Real-money flags are HARD-LOCKED to false. They can only ever become true if the
 * operator sets REAL_MONEY_AUTHORIZED=true in the server environment after legal
 * and provider authorisation — and even then no payment provider is implemented.
 */
export const LOCKED_FLAGS = ['LIVE_PURCHASE_ENABLED', 'PAYMENT_ENABLED', 'PRIZE_SETTLEMENT_ENABLED', 'OFFICIAL_FEED_ENABLED'] as const;

export const DEFAULT_SETTINGS: Record<string, unknown> = {
  DEMO_MODE: true,
  LIVE_PURCHASE_ENABLED: false,
  PAYMENT_ENABLED: false,
  PRIZE_SETTLEMENT_ENABLED: false,
  OFFICIAL_FEED_ENABLED: false,
  siteName: 'LOTTO DAY',
  supportPhone: '02-000-0000 (DEMO)',
  supportEmail: 'support@lottoday.demo',
  maintenanceMode: false,
  maxTicketsPerOrder: 20,
  maxDemoTopup: 10000,
  registrationOpen: true,
};

@Injectable()
export class SettingsService {
  constructor(private readonly db: Database) {}

  static realMoneyAuthorized() { return process.env.REAL_MONEY_AUTHORIZED === 'true'; }

  async all(): Promise<Record<string, unknown>> {
    const rows = await this.db.systemSetting.findMany();
    const out: Record<string, unknown> = { ...DEFAULT_SETTINGS };
    for (const r of rows) out[r.key] = r.value;
    if (!SettingsService.realMoneyAuthorized()) for (const f of LOCKED_FLAGS) out[f] = false;
    out.DEMO_MODE = true;
    return out;
  }

  async get<T>(key: string): Promise<T> { return (await this.all())[key] as T; }

  async publicConfig() {
    const s = await this.all();
    return {
      siteName: s.siteName, supportPhone: s.supportPhone, supportEmail: s.supportEmail, maintenanceMode: s.maintenanceMode,
      registrationOpen: s.registrationOpen, maxTicketsPerOrder: s.maxTicketsPerOrder, maxDemoTopup: s.maxDemoTopup,
      flags: Object.fromEntries(['DEMO_MODE', ...LOCKED_FLAGS].map((k) => [k, s[k]])),
    };
  }

  async update(patch: Record<string, unknown>, user: AuthUser, ip?: string) {
    const keys = Object.keys(patch);
    if (keys.length === 0) throw new BadRequestException('nothing to update');
    for (const k of keys) {
      if (!(k in DEFAULT_SETTINGS)) throw new BadRequestException(`unknown setting ${k}`);
      if (k === 'DEMO_MODE' && patch[k] !== true) throw new ForbiddenException('DEMO_MODE cannot be disabled in this build');
      if ((LOCKED_FLAGS as readonly string[]).includes(k) && patch[k] !== false && !SettingsService.realMoneyAuthorized()) {
        throw new ForbiddenException(`${k} is locked: real-money operations are not authorised for this deployment`);
      }
      if (typeof patch[k] !== typeof DEFAULT_SETTINGS[k]) throw new BadRequestException(`setting ${k} must be ${typeof DEFAULT_SETTINGS[k]}`);
    }
    const before = await this.all();
    await this.db.$transaction(async (tx) => {
      for (const k of keys) {
        await tx.systemSetting.upsert({
          where: { key: k }, create: { key: k, value: patch[k] as Prisma.InputJsonValue, updatedBy: user.email },
          update: { value: patch[k] as Prisma.InputJsonValue, updatedBy: user.email },
        });
      }
      await writeAudit(tx, {
        actor: user.email, actorId: user.id, action: 'UPDATE_SETTINGS', entityType: 'settings', entityId: 'system', ip,
        before: Object.fromEntries(keys.map((k) => [k, before[k]])), after: patch,
      });
    });
    return this.all();
  }
}
