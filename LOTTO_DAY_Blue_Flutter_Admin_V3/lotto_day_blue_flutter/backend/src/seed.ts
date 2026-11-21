/**
 * Idempotent demo/test seed. Run: `npm run db:seed` (dev) or `node dist/seed.js` (prod image).
 * Staff passwords come from SEED_STAFF_PASSWORD (default Admin@1234 — change it for any shared deployment).
 * External-market results are NEVER seeded as published: they stay in the review workflow.
 */
import { DrawStatus, KycStatus, PrismaClient, Role, TicketStatus, WalletTxType } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { Database, writeAudit } from './common/database';
import { bangkokToday, generateDemoResults, POSITIONS, zonedTime } from './common/rules';
import { generateTickets, receiptNo } from './commerce';
import { MARKET_SEED } from './lottery.service';

export const DEMO_USER = { email: 'user@lottoday.demo', password: 'User@1234' };
export const STAFF = [
  { email: 'superadmin@lottoday.demo', displayName: 'ผู้ดูแลสูงสุด', role: Role.SUPER_ADMIN },
  { email: 'admin@lottoday.demo', displayName: 'ผู้ดูแลระบบ', role: Role.ADMIN },
  { email: 'editor@lottoday.demo', displayName: 'ผู้บันทึกผล', role: Role.RESULT_EDITOR },
  { email: 'reviewer@lottoday.demo', displayName: 'ผู้ตรวจสอบผล', role: Role.REVIEWER },
  { email: 'auditor@lottoday.demo', displayName: 'ผู้ตรวจสอบบัญชี', role: Role.AUDITOR },
];

const addDays = (iso: string, n: number) => new Date(new Date(`${iso}T00:00:00Z`).getTime() + n * 86400_000).toISOString().substring(0, 10);

export async function seed(db: PrismaClient, opts: { log?: boolean } = {}) {
  const log = (m: string) => opts.log && console.log(`[seed] ${m}`);
  const staffPassword = process.env.SEED_STAFF_PASSWORD || 'Admin@1234';
  const sys = { actor: 'system-seed', action: 'SEED', entityType: 'system' };

  for (const m of MARKET_SEED) {
    await db.lotteryMarket.upsert({ where: { id: m.id }, update: {}, create: { ...m, drawWeekdays: [...m.drawWeekdays], allowedDigits: [2, 3, 4], allowedPositions: [...POSITIONS] } });
  }
  log('markets ok');

  const staffHash = await bcrypt.hash(staffPassword, 10);
  for (const s of STAFF) {
    await db.user.upsert({ where: { email: s.email }, update: {}, create: { ...s, passwordHash: staffHash, kycStatus: KycStatus.VERIFIED } });
  }
  const existingUser = await db.user.findUnique({ where: { email: DEMO_USER.email } });
  if (existingUser) { log('demo data already present — skipping transactional seed'); return; }

  const user = await db.user.create({ data: {
    email: DEMO_USER.email, displayName: 'สมชาย ใจดี', phone: '0812341234', role: Role.USER, kycStatus: KycStatus.VERIFIED,
    passwordHash: await bcrypt.hash(DEMO_USER.password, 10), demoBalance: 0,
  } });
  const user2 = await db.user.create({ data: {
    email: 'somying@lottoday.demo', displayName: 'สมหญิง รักดี', phone: '0898887777', role: Role.USER, kycStatus: KycStatus.PENDING,
    passwordHash: await bcrypt.hash(DEMO_USER.password, 10), demoBalance: 500,
  } });
  const editor = await db.user.findUniqueOrThrow({ where: { email: 'editor@lottoday.demo' } });
  const reviewer = await db.user.findUniqueOrThrow({ where: { email: 'reviewer@lottoday.demo' } });
  const markets = await db.lotteryMarket.findMany();
  const mk = (id: string) => markets.find((m) => m.id === id)!;
  const today = bangkokToday();

  await db.$transaction(async (tx) => {
    // ---- Daily (internal demo): 10 past published draws with tickets, today + tomorrow open
    for (let i = -10; i <= 1; i++) {
      const day = addDays(today, i);
      const m = mk('daily');
      const published = i < 0;
      const draw = await tx.lotteryDraw.create({ data: {
        marketId: 'daily', drawDate: new Date(`${day}T00:00:00Z`), opensAt: zonedTime(addDays(day, -1), m.closeTime), closesAt: zonedTime(day, m.closeTime),
        status: published ? DrawStatus.PUBLISHED : DrawStatus.SCHEDULED, createdById: editor.id,
        ...(published ? {
          results: generateDemoResults(m.allowedDigits, m.allowedPositions), sourceNote: 'ผลสุ่ม DEMO (seed)', editedById: editor.id, submittedById: editor.id,
          submittedAt: zonedTime(day, '15:45'), reviewedById: reviewer.id, reviewedAt: zonedTime(day, '15:50'), approvedBy: reviewer.email,
          publishedById: reviewer.id, publishedAt: zonedTime(day, m.resultTime), version: 5,
        } : {}),
      } });
      await generateTickets(tx, draw.id, published ? 30 : 80, m.ticketPrice);
    }
    // ---- Lao / Vietnam: today open, plus review-workflow examples (never published by seed)
    for (const id of ['lao', 'vietnam']) {
      const m = mk(id);
      const todayDraw = await tx.lotteryDraw.create({ data: { marketId: id, drawDate: new Date(`${today}T00:00:00Z`), opensAt: zonedTime(addDays(today, -1), m.closeTime), closesAt: zonedTime(today, m.closeTime), createdById: editor.id } });
      await generateTickets(tx, todayDraw.id, 40, m.ticketPrice);
      await tx.lotteryDraw.create({ data: {
        marketId: id, drawDate: new Date(`${addDays(today, -1)}T00:00:00Z`), opensAt: zonedTime(addDays(today, -2), m.closeTime), closesAt: zonedTime(addDays(today, -1), m.closeTime),
        status: DrawStatus.AWAITING_REVIEW, results: generateDemoResults(m.allowedDigits, m.allowedPositions), sourceName: 'ตัวอย่างแหล่งประกาศ (ทดสอบ)',
        sourceUrl: 'https://example.org/official-results', sourceCapturedAt: new Date(), sourceNote: 'ข้อมูลทดสอบสำหรับขั้นตอนตรวจสอบ — ไม่ใช่ผลจริง',
        createdById: editor.id, editedById: editor.id, submittedById: editor.id, submittedAt: new Date(), version: 3,
      } });
      await tx.lotteryDraw.create({ data: {
        marketId: id, drawDate: new Date(`${addDays(today, -2)}T00:00:00Z`), opensAt: zonedTime(addDays(today, -3), m.closeTime), closesAt: zonedTime(addDays(today, -2), m.closeTime),
        status: DrawStatus.DRAFT, results: { '2:bottom': '00' }, sourceNote: 'ร่างทดสอบ — รอข้อมูลจากแหล่งประกาศ', createdById: editor.id, editedById: editor.id, version: 2,
      } });
    }
    // ---- Thai: next 1st/16th draw, long sales window
    const t = new Date(`${today}T00:00:00Z`);
    let next = t.getUTCDate() < 16 ? new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), 16)) : new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth() + 1, 1));
    if (next.toISOString().substring(0, 10) === today) next = new Date(next.getTime() + 15 * 86400_000);
    const thaiDay = next.toISOString().substring(0, 10);
    const thai = await tx.lotteryDraw.create({ data: { marketId: 'thai', drawDate: next, opensAt: zonedTime(addDays(today, -1), '06:00'), closesAt: zonedTime(addDays(thaiDay, -1), mk('thai').closeTime), createdById: editor.id } });
    await generateTickets(tx, thai.id, 120, mk('thai').ticketPrice);
    await writeAudit(tx, { ...sys, entityId: 'markets+draws', after: { today, thaiDay } });
  }, { timeout: 60_000 });
  log('draws + tickets ok');

  // ---- Wallet + historic demo orders for สมชาย
  await db.$transaction(async (tx) => {
    let balance = 0;
    const topup = async (amount: number, at: Date) => {
      balance += amount;
      await tx.walletTransaction.create({ data: { userId: user.id, type: WalletTxType.TOPUP_DEMO, amount, balanceAfter: balance, reference: receiptNo(), note: 'เติมเครดิตจำลอง (seed)', createdAt: at } });
    };
    await topup(1500, new Date(Date.now() - 9 * 86400_000));
    const pastDaily = await tx.lotteryDraw.findMany({ where: { marketId: 'daily', status: DrawStatus.PUBLISHED }, orderBy: { drawDate: 'desc' }, take: 3 });
    for (const [idx, d] of pastDaily.entries()) {
      const tix = await tx.demoTicket.findMany({ where: { drawId: d.id, status: TicketStatus.AVAILABLE }, take: 2 });
      // Make one ticket match the last-2 "bottom" result so the result-check UI shows a hit.
      const res = d.results as Record<string, string>;
      if (idx === 0 && res['2:bottom']) {
        const n = `1234${res['2:bottom']}`;
        if (!(await tx.demoTicket.findFirst({ where: { drawId: d.id, number: n } }))) tix[0] = await tx.demoTicket.create({ data: { drawId: d.id, number: n, price: tix[0].price } });
      }
      const total = tix.reduce((s, x) => s + x.price, 0);
      balance -= total;
      const at = new Date((d.closesAt ?? new Date()).getTime() - 3 * 3600_000);
      const order = await tx.order.create({ data: { receiptNo: receiptNo(), userId: user.id, total, createdAt: at,
        items: { create: tix.map((x) => ({ ticketId: x.id, number: x.number, drawId: d.id, price: x.price })) } } });
      await tx.demoTicket.updateMany({ where: { id: { in: tix.map((x) => x.id) } }, data: { status: TicketStatus.SOLD } });
      await tx.walletTransaction.create({ data: { userId: user.id, type: WalletTxType.PURCHASE_DEMO, amount: -total, balanceAfter: balance, reference: order.receiptNo, note: `ซื้อสลาก ${tix.length} ใบ (DEMO)`, createdAt: at } });
    }
    await topup(500, new Date(Date.now() - 86400_000));
    await tx.user.update({ where: { id: user.id }, data: { demoBalance: balance } });
    await tx.walletTransaction.create({ data: { userId: user2.id, type: WalletTxType.TOPUP_DEMO, amount: 500, balanceAfter: 500, reference: receiptNo(), note: 'เติมเครดิตจำลอง (seed)' } });

    await tx.announcement.createMany({ data: [
      { title: 'ยินดีต้อนรับสู่ LOTTO DAY (ระบบสาธิต)', body: 'ระบบนี้เป็นเวอร์ชันสาธิต ธุรกรรมทั้งหมดใช้เครดิตจำลอง ไม่มีการซื้อขายหรือชำระเงินจริง', category: 'SYSTEM', pinned: true, published: true, publishedAt: new Date() },
      { title: 'ผลหวยรายวันประกาศเวลา 16:00 น.', body: 'หวยรายวัน (DEMO) ปิดรับ 15:30 น. และประกาศผลจำลองเวลา 16:00 น. ทุกวัน', category: 'RESULT', published: true, publishedAt: new Date() },
      { title: 'ผลหวยภายนอกต้องผ่านการตรวจสอบ', body: 'ผลหวยลาว เวียดนาม และไทย จะแสดงหลังจากผู้ตรวจสอบยืนยันกับแหล่งประกาศอย่างเป็นทางการแล้วเท่านั้น', category: 'NEWS', published: true, publishedAt: new Date() },
      { title: '(ร่าง) ปิดปรับปรุงระบบ', body: 'ประกาศร่างสำหรับทดสอบ ยังไม่เผยแพร่', category: 'SYSTEM', published: false },
    ] });
    await tx.notification.createMany({ data: [
      { userId: user.id, title: 'ยินดีต้อนรับ คุณสมชาย', body: 'บัญชีสาธิตพร้อมใช้งาน เครดิตจำลองไม่สามารถแลกเป็นเงินจริงได้' },
      { userId: user.id, title: 'ประกาศผลหวยรายวัน', body: 'ผลหวยรายวันงวดล่าสุดประกาศแล้ว ตรวจสลากของคุณได้เลย', link: '/app/my-tickets' },
    ] });
    await writeAudit(tx, { ...sys, entityId: 'demo-users', after: { users: [DEMO_USER.email, 'somying@lottoday.demo'] } });
  }, { timeout: 60_000 });
  log('users, orders, wallet, announcements ok');
}

if (require.main === module) {
  const db = new Database();
  seed(db, { log: true }).then(() => db.$disconnect()).catch(async (e) => { console.error(e); await db.$disconnect(); process.exit(1); });
}
