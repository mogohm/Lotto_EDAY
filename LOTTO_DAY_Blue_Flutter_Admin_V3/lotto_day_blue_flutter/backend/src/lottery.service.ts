import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DrawStatus, LotteryDraw, LotteryKind, LotteryMarket, Prisma, ResultSource } from '@prisma/client';
import { AuthUser } from './common/auth';
import { Database, Tx, writeAudit } from './common/database';
import {
  assertExternalSubmittable, assertSeparationOfDuties, bangkokToday, DIGITS, generateDemoResults, matchTicket, missingKeys,
  nextStatus, POSITIONS, salesState, Transition, validateResults, zonedTime,
} from './common/rules';

export const MARKET_SEED = [
  { id: 'daily', nameTh: 'หวยรายวัน (DEMO)', nameEn: 'Daily (demo)', kind: LotteryKind.DAILY, source: ResultSource.INTERNAL_DEMO, sortOrder: 1,
    description: 'ผลกำหนดโดยผู้ดูแลหรือสุ่มแบบ DEMO ทุกวัน', openTime: '06:00', closeTime: '15:30', resultTime: '16:00', drawWeekdays: [0, 1, 2, 3, 4, 5, 6] },
  { id: 'lao', nameTh: 'หวยลาว', nameEn: 'Lao', kind: LotteryKind.LAO, source: ResultSource.EXTERNAL_UNVERIFIED, sortOrder: 2,
    description: 'ผลภายนอก ต้องอ้างอิงแหล่งประกาศและผ่านการตรวจสอบโดยผู้ตรวจคนละคนก่อนเผยแพร่', openTime: '06:00', closeTime: '20:00', resultTime: '20:30', drawWeekdays: [1, 2, 3, 4, 5] },
  { id: 'vietnam', nameTh: 'หวยเวียดนาม', nameEn: 'Vietnam', kind: LotteryKind.VIETNAM, source: ResultSource.EXTERNAL_UNVERIFIED, sortOrder: 3,
    description: 'ผลภายนอก ต้องอ้างอิงแหล่งประกาศและผ่านการตรวจสอบโดยผู้ตรวจคนละคนก่อนเผยแพร่', openTime: '06:00', closeTime: '18:00', resultTime: '18:30', drawWeekdays: [0, 1, 2, 3, 4, 5, 6] },
  { id: 'thai', nameTh: 'หวยไทย', nameEn: 'Thai', kind: LotteryKind.THAI, source: ResultSource.EXTERNAL_UNVERIFIED, sortOrder: 4,
    description: 'ผลภายนอก ต้องอ้างอิงแหล่งประกาศและผ่านการตรวจสอบโดยผู้ตรวจคนละคนก่อนเผยแพร่', openTime: '06:00', closeTime: '14:00', resultTime: '16:00', drawWeekdays: [] },
] as const;

export interface MarketInput {
  id?: string; nameTh?: string; nameEn?: string; kind?: LotteryKind; description?: string; allowedDigits?: number[];
  allowedPositions?: string[]; enabled?: boolean; openTime?: string; closeTime?: string; resultTime?: string;
  drawWeekdays?: number[]; ticketPrice?: number; sortOrder?: number; expectedVersion?: number;
}
export interface DraftInput {
  results: Record<string, string>; sourceNote?: string; sourceName?: string; sourceUrl?: string; sourceCapturedAt?: string; expectedVersion: string | number;
}
export interface DrawFilter { marketId?: string; status?: DrawStatus; from?: string; to?: string; take?: number }

const isExternal = (m: Pick<LotteryMarket, 'kind'>) => m.kind !== LotteryKind.DAILY;

@Injectable()
export class LotteryService {
  constructor(private readonly db: Database) {}

  // ---------- presentation ----------
  presentDraw(d: LotteryDraw & { market?: LotteryMarket }, now = new Date()) {
    return { ...d, drawDate: d.drawDate.toISOString().substring(0, 10), salesState: salesState(now, d.opensAt, d.closesAt, d.status) };
  }
  /** Public projection hides draft/unapproved result values. */
  presentPublic(d: LotteryDraw & { market?: LotteryMarket }) {
    const p = this.presentDraw(d);
    const visible = d.status === DrawStatus.PUBLISHED;
    return {
      id: p.id, marketId: p.marketId, drawDate: p.drawDate, opensAt: p.opensAt, closesAt: p.closesAt, status: p.status, salesState: p.salesState,
      results: visible ? p.results : {}, publishedAt: p.publishedAt, sourceName: visible ? p.sourceName : null, sourceUrl: visible ? p.sourceUrl : null,
      sourceVerified: p.sourceVerified, market: d.market ? { id: d.market.id, nameTh: d.market.nameTh, kind: d.market.kind, source: d.market.source } : undefined,
    };
  }

  // ---------- markets ----------
  markets(includeDisabled = false) {
    return this.db.lotteryMarket.findMany({ where: includeDisabled ? {} : { enabled: true }, orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }] });
  }

  private validateMarket(input: MarketInput) {
    if (input.allowedDigits) {
      if (input.allowedDigits.length === 0 || input.allowedDigits.some((d) => !(DIGITS as readonly number[]).includes(d))) throw new BadRequestException('allowedDigits must be a non-empty subset of [2,3,4]');
    }
    if (input.allowedPositions) {
      if (input.allowedPositions.length === 0 || input.allowedPositions.some((p) => !(POSITIONS as readonly string[]).includes(p))) throw new BadRequestException('allowedPositions must be a non-empty subset of front/back/top/bottom');
    }
    for (const t of [input.openTime, input.closeTime, input.resultTime]) if (t !== undefined && !/^([01]\d|2[0-3]):[0-5]\d$/.test(t)) throw new BadRequestException('time must be HH:mm');
    if (input.openTime && input.closeTime && input.openTime >= input.closeTime) throw new BadRequestException('openTime must be before closeTime');
    if (input.drawWeekdays && input.drawWeekdays.some((d) => !Number.isInteger(d) || d < 0 || d > 6)) throw new BadRequestException('drawWeekdays must be 0..6');
    if (input.ticketPrice !== undefined && (!Number.isInteger(input.ticketPrice) || input.ticketPrice < 1 || input.ticketPrice > 10000)) throw new BadRequestException('ticketPrice 1..10000');
  }

  async createMarket(input: MarketInput, user: AuthUser, ip?: string) {
    if (!input.id || !/^[a-z][a-z0-9-]{1,30}$/.test(input.id)) throw new BadRequestException('id must be lowercase slug');
    if (!input.nameTh || !input.kind) throw new BadRequestException('nameTh and kind required');
    this.validateMarket(input);
    return this.db.$transaction(async (tx) => {
      const m = await tx.lotteryMarket.create({ data: {
        id: input.id!, nameTh: input.nameTh!, nameEn: input.nameEn ?? '', kind: input.kind!, description: input.description ?? '',
        allowedDigits: [...(input.allowedDigits ?? [2, 3, 4])].sort(), allowedPositions: input.allowedPositions ?? [...POSITIONS],
        source: input.kind === LotteryKind.DAILY ? ResultSource.INTERNAL_DEMO : ResultSource.EXTERNAL_UNVERIFIED,
        enabled: input.enabled ?? true, openTime: input.openTime, closeTime: input.closeTime, resultTime: input.resultTime,
        drawWeekdays: input.drawWeekdays, ticketPrice: input.ticketPrice, sortOrder: input.sortOrder ?? 99,
      } });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action: 'CREATE_MARKET', entityType: 'market', entityId: m.id, after: m, ip });
      return m;
    });
  }

  async updateMarket(id: string, input: MarketInput, user: AuthUser, ip?: string) {
    this.validateMarket(input);
    return this.db.$transaction(async (tx) => {
      const before = await tx.lotteryMarket.findUnique({ where: { id } });
      if (!before) throw new NotFoundException('market not found');
      if (input.expectedVersion !== undefined && input.expectedVersion !== before.version) throw new ConflictException('stale version: market changed by someone else');
      const open = input.openTime ?? before.openTime, close = input.closeTime ?? before.closeTime;
      if (open >= close) throw new BadRequestException('openTime must be before closeTime');
      const m = await tx.lotteryMarket.update({ where: { id }, data: {
        nameTh: input.nameTh, nameEn: input.nameEn, description: input.description, enabled: input.enabled,
        allowedDigits: input.allowedDigits ? [...input.allowedDigits].sort() : undefined, allowedPositions: input.allowedPositions,
        openTime: input.openTime, closeTime: input.closeTime, resultTime: input.resultTime, drawWeekdays: input.drawWeekdays,
        ticketPrice: input.ticketPrice, sortOrder: input.sortOrder, version: { increment: 1 },
      } });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action: 'UPDATE_MARKET', entityType: 'market', entityId: id, before, after: m, ip });
      return m;
    });
  }

  // ---------- draws ----------
  async draws(f: DrawFilter = {}) {
    const where: Prisma.LotteryDrawWhereInput = {};
    if (f.marketId) where.marketId = f.marketId;
    if (f.status) where.status = f.status;
    if (f.from || f.to) where.drawDate = { gte: f.from ? new Date(`${f.from}T00:00:00Z`) : undefined, lte: f.to ? new Date(`${f.to}T00:00:00Z`) : undefined };
    const rows = await this.db.lotteryDraw.findMany({ where, include: { market: true }, orderBy: [{ drawDate: 'desc' }, { marketId: 'asc' }], take: Math.min(f.take ?? 200, 500) });
    return rows.map((d) => this.presentDraw(d));
  }

  async draw(id: string) {
    const d = await this.db.lotteryDraw.findUnique({ where: { id }, include: { market: true, _count: { select: { tickets: true } } } });
    if (!d) throw new NotFoundException('draw not found');
    return this.presentDraw(d);
  }

  async published(marketId?: string, take = 30) {
    const rows = await this.db.lotteryDraw.findMany({ where: { status: DrawStatus.PUBLISHED, marketId, market: { enabled: true } }, include: { market: true }, orderBy: { drawDate: 'desc' }, take: Math.min(take, 100) });
    return rows.map((d) => this.presentPublic(d));
  }

  async publicDraws(marketId?: string) {
    const rows = await this.db.lotteryDraw.findMany({ where: { marketId, market: { enabled: true }, status: { not: DrawStatus.CANCELLED } }, include: { market: true }, orderBy: { drawDate: 'desc' }, take: 60 });
    return rows.map((d) => this.presentPublic(d));
  }

  async createDraw(marketId: string, date: string, user: AuthUser, opts: { openTime?: string; closeTime?: string } = {}, ip?: string, tx?: Tx) {
    const run = async (t: Tx) => {
      const market = await t.lotteryMarket.findUnique({ where: { id: marketId } });
      if (!market) throw new NotFoundException('market not found');
      const day = date.substring(0, 10);
      const drawDate = new Date(`${day}T00:00:00.000Z`);
      if (Number.isNaN(drawDate.valueOf())) throw new BadRequestException('date invalid');
      const opensAt = zonedTime(day, opts.openTime ?? market.openTime);
      const closesAt = zonedTime(day, opts.closeTime ?? market.closeTime);
      if (opensAt >= closesAt) throw new BadRequestException('openTime must be before closeTime');
      const existing = await t.lotteryDraw.findUnique({ where: { marketId_drawDate: { marketId, drawDate } } });
      if (existing) throw new ConflictException('draw already exists for this market and date');
      const d = await t.lotteryDraw.create({ data: { marketId, drawDate, opensAt, closesAt, createdById: user.id } });
      await writeAudit(t, { actor: user.email, actorId: user.id, action: 'CREATE_DRAW', entityType: 'draw', entityId: d.id, after: { marketId, date: day, opensAt, closesAt }, ip });
      return this.presentDraw(d);
    };
    return tx ? run(tx) : this.db.$transaction(run);
  }

  /** Creates draws for the next `days` calendar days that match the market's weekday schedule; skips existing. */
  async createUpcoming(marketId: string, days: number, user: AuthUser, ip?: string) {
    if (!Number.isInteger(days) || days < 1 || days > 31) throw new BadRequestException('days must be 1..31');
    const market = await this.db.lotteryMarket.findUnique({ where: { id: marketId } });
    if (!market) throw new NotFoundException('market not found');
    const created: string[] = [];
    const today = new Date(`${bangkokToday()}T00:00:00Z`);
    for (let i = 0; i < days; i++) {
      const day = new Date(today.getTime() + i * 86400_000);
      if (!market.drawWeekdays.includes(day.getUTCDay())) continue;
      const iso = day.toISOString().substring(0, 10);
      const exists = await this.db.lotteryDraw.findUnique({ where: { marketId_drawDate: { marketId, drawDate: day } } });
      if (exists) continue;
      await this.createDraw(marketId, iso, user, {}, ip);
      created.push(iso);
    }
    return { created };
  }

  async updateSchedule(id: string, dto: { opensAt?: string; closesAt?: string; expectedVersion: number }, user: AuthUser, ip?: string) {
    return this.db.$transaction(async (tx) => {
      const d = await this.lockDraw(tx, id);
      if (!['SCHEDULED', 'DRAFT'].includes(d.status)) throw new ConflictException('schedule can only change before review');
      const opensAt = dto.opensAt ? new Date(dto.opensAt) : d.opensAt;
      const closesAt = dto.closesAt ? new Date(dto.closesAt) : d.closesAt;
      if ((opensAt && Number.isNaN(opensAt.valueOf())) || (closesAt && Number.isNaN(closesAt.valueOf()))) throw new BadRequestException('invalid datetime');
      if (opensAt && closesAt && opensAt >= closesAt) throw new BadRequestException('opensAt must be before closesAt');
      const next = await this.bump(tx, d, dto.expectedVersion, { opensAt, closesAt });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action: 'UPDATE_SCHEDULE', entityType: 'draw', entityId: id, ip,
        before: { opensAt: d.opensAt, closesAt: d.closesAt }, after: { opensAt, closesAt } });
      return this.presentDraw(next);
    });
  }

  private async lockDraw(tx: Tx, id: string) {
    await tx.$executeRaw`SELECT id FROM "LotteryDraw" WHERE id = ${id} FOR UPDATE`;
    const d = await tx.lotteryDraw.findUnique({ where: { id }, include: { market: true } });
    if (!d) throw new NotFoundException('draw not found');
    return d;
  }

  /** Optimistic concurrency: update only if version matches. */
  private async bump(tx: Tx, d: LotteryDraw, expectedVersion: number | string | undefined, data: Prisma.LotteryDrawUpdateManyMutationInput) {
    const version = expectedVersion === undefined ? d.version : Number(expectedVersion);
    if (!Number.isInteger(version) || version < 1) throw new BadRequestException('version invalid');
    const res = await tx.lotteryDraw.updateMany({ where: { id: d.id, version }, data: { ...data, version: { increment: 1 } } });
    if (res.count !== 1) throw new ConflictException('stale version: draw was changed by someone else, reload and retry');
    return tx.lotteryDraw.findUniqueOrThrow({ where: { id: d.id }, include: { market: true } });
  }

  async saveDraft(id: string, dto: DraftInput, user: AuthUser, ip?: string, action = 'SAVE_DRAFT') {
    return this.db.$transaction(async (tx) => {
      const d = await this.lockDraw(tx, id);
      const to = nextStatus(d.status, 'SAVE_DRAFT');
      const results = validateResults(dto.results, d.market.allowedDigits, d.market.allowedPositions);
      let capturedAt: Date | null | undefined = undefined;
      if (dto.sourceCapturedAt !== undefined) {
        capturedAt = dto.sourceCapturedAt ? new Date(dto.sourceCapturedAt) : null;
        if (capturedAt && Number.isNaN(capturedAt.valueOf())) throw new BadRequestException('sourceCapturedAt invalid');
      }
      if (dto.sourceUrl && !/^https?:\/\//i.test(dto.sourceUrl)) throw new BadRequestException('sourceUrl must start with http(s)://');
      const next = await this.bump(tx, d, dto.expectedVersion, {
        results, status: to, sourceNote: dto.sourceNote ?? d.sourceNote, sourceName: dto.sourceName ?? d.sourceName,
        sourceUrl: dto.sourceUrl === undefined ? d.sourceUrl : dto.sourceUrl || null, sourceCapturedAt: capturedAt, editedById: user.id,
        sourceVerified: false,
      });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action, entityType: 'draw', entityId: id, ip,
        before: { status: d.status, version: d.version, results: d.results }, after: { status: next.status, version: next.version, results } });
      return this.presentDraw(next);
    });
  }

  async generateDemo(id: string, user: AuthUser, ip?: string) {
    const d = await this.db.lotteryDraw.findUnique({ where: { id }, include: { market: true } });
    if (!d) throw new NotFoundException('draw not found');
    if (d.market.kind !== LotteryKind.DAILY) throw new ForbiddenException('daily demo only: external results must come from an official source');
    const results = generateDemoResults(d.market.allowedDigits, d.market.allowedPositions);
    return this.saveDraft(id, { results, sourceNote: 'ผลสุ่ม DEMO (cryptographic RNG) — ไม่ใช่ผลรางวัลจริง', expectedVersion: d.version }, user, ip, 'GENERATE_DEMO');
  }

  private async transition(id: string, action: Transition, user: AuthUser, expectedVersion: number | string | undefined, ip: string | undefined,
    extra: (d: LotteryDraw & { market: LotteryMarket }) => Prisma.LotteryDrawUpdateManyMutationInput = () => ({}), guard?: (d: LotteryDraw & { market: LotteryMarket }) => void, note?: string) {
    return this.db.$transaction(async (tx) => {
      const d = await this.lockDraw(tx, id);
      const to = nextStatus(d.status, action);
      guard?.(d);
      const next = await this.bump(tx, d, expectedVersion, { status: to, ...extra(d) });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action, entityType: 'draw', entityId: id, ip,
        before: { status: d.status, version: d.version }, after: { status: to, version: next.version, note } });
      if (to === DrawStatus.PUBLISHED) await this.notifyHolders(tx, next);
      return this.presentDraw(next);
    });
  }

  submit(id: string, user: AuthUser, expectedVersion?: number | string, ip?: string) {
    return this.transition(id, 'SUBMIT', user, expectedVersion, ip, () => ({ submittedById: user.id, submittedAt: new Date() }), (d) => {
      const results = d.results as Record<string, string>;
      const missing = missingKeys(results, d.market.allowedDigits, d.market.allowedPositions);
      if (missing.length) throw new BadRequestException(`กรอกผลให้ครบก่อนส่งตรวจ: ${missing.join(', ')}`);
      assertExternalSubmittable(isExternal(d.market), d);
    });
  }

  approve(id: string, user: AuthUser, expectedVersion?: number | string, note?: string, ip?: string) {
    return this.transition(id, 'APPROVE', user, expectedVersion, ip,
      (d) => ({ reviewedById: user.id, reviewedAt: new Date(), reviewNote: note ?? null, approvedBy: user.email, sourceVerified: isExternal(d.market) }),
      (d) => assertSeparationOfDuties(isExternal(d.market), d.submittedById, user.id), note);
  }

  reject(id: string, user: AuthUser, note: string, expectedVersion?: number | string, ip?: string) {
    if (!note?.trim()) throw new BadRequestException('กรุณาระบุเหตุผลที่ส่งกลับแก้ไข');
    return this.transition(id, 'REJECT', user, expectedVersion, ip,
      () => ({ reviewedById: user.id, reviewedAt: new Date(), reviewNote: note, sourceVerified: false, approvedBy: null }), undefined, note);
  }

  publish(id: string, user: AuthUser, expectedVersion?: number | string, ip?: string) {
    return this.transition(id, 'PUBLISH', user, expectedVersion, ip, () => ({ publishedById: user.id, publishedAt: new Date() }), (d) => {
      if (isExternal(d.market) && !d.sourceVerified) throw new ForbiddenException('external results must be source-verified by a reviewer before publishing');
    });
  }

  cancel(id: string, user: AuthUser, reason: string, expectedVersion?: number | string, ip?: string) {
    if (!reason?.trim()) throw new BadRequestException('กรุณาระบุเหตุผลการยกเลิก');
    return this.transition(id, 'CANCEL', user, expectedVersion, ip, () => ({ cancelReason: reason }), undefined, reason);
  }

  /** V3 legacy one-shot endpoint: daily DEMO only — submit, self-approve and publish atomically. */
  async publishDemo(id: string, user: AuthUser, ip?: string) {
    const d = await this.db.lotteryDraw.findUnique({ where: { id }, include: { market: true } });
    if (!d) throw new NotFoundException('draw not found');
    if (d.market.kind !== LotteryKind.DAILY) throw new ForbiddenException('external results require official verification workflow');
    if (d.status !== DrawStatus.DRAFT || Object.keys(d.results as object).length === 0) throw new ConflictException('save a draft first');
    await this.submit(id, user, undefined, ip);
    await this.approve(id, user, undefined, 'daily demo self-approval', ip);
    return this.publish(id, user, undefined, ip);
  }

  private async notifyHolders(tx: Tx, d: LotteryDraw & { market: LotteryMarket }) {
    const holders = await tx.orderItem.findMany({ where: { drawId: d.id, order: { status: 'CONFIRMED_DEMO' } }, select: { order: { select: { userId: true } } } });
    const userIds = [...new Set(holders.map((h) => h.order.userId))];
    if (!userIds.length) return;
    await tx.notification.createMany({ data: userIds.map((userId) => ({
      userId, title: `ประกาศผล ${d.market.nameTh}`, body: `งวด ${d.drawDate.toISOString().substring(0, 10)} ประกาศผลแล้ว ตรวจสลากของคุณได้เลย`, link: '/app/my-tickets',
    })) });
  }

  // ---------- public check ----------
  async check(number: string, drawId?: string, marketId?: string) {
    const draw = drawId
      ? await this.db.lotteryDraw.findFirst({ where: { id: drawId, status: DrawStatus.PUBLISHED }, include: { market: true } })
      : await this.db.lotteryDraw.findFirst({ where: { status: DrawStatus.PUBLISHED, marketId }, include: { market: true }, orderBy: { drawDate: 'desc' } });
    if (!draw) throw new NotFoundException('ยังไม่มีผลที่ประกาศสำหรับงวดนี้');
    const matches = matchTicket(number, draw.results as Record<string, string>);
    return { number, draw: this.presentPublic(draw), matches, disclaimer: 'ผลการเทียบเลขแบบ DEMO เท่านั้น ไม่ใช่การยืนยันสิทธิ์รับรางวัลและไม่มีการจ่ายเงินจริง' };
  }

  // ---------- seed ----------
  async seedMarkets() {
    for (const m of MARKET_SEED) {
      await this.db.lotteryMarket.upsert({
        where: { id: m.id },
        create: { ...m, drawWeekdays: [...m.drawWeekdays], allowedDigits: [2, 3, 4], allowedPositions: [...POSITIONS] },
        update: {},
      });
    }
    return { ok: true, markets: MARKET_SEED.length };
  }
}
