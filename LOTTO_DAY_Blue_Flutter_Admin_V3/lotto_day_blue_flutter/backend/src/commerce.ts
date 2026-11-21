/**
 * DEMO commerce: catalogue, cart, checkout and wallet use SIMULATED, non-redeemable credits.
 * No payment provider exists. Real-money flags are hard-locked in SettingsService.
 */
import {
  BadRequestException, Body, ConflictException, Controller, Delete, ForbiddenException, Get, HttpCode, Injectable, NotFoundException, Param, Post, Query,
} from '@nestjs/common';
import { DrawStatus, OrderStatus, Prisma, TicketStatus, WalletTxStatus, WalletTxType } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { randomBytes, randomInt } from 'node:crypto';
import { AuthUser, ClientIp, CurrentUser, Public } from './common/auth';
import { Database, Tx, writeAudit } from './common/database';
import { matchTicket, salesState } from './common/rules';
import { SettingsService } from './common/settings.service';

class CartDto { @IsString() ticketId!: string }
class AmountDto {
  @Type(() => Number) @IsInt() @Min(20) @Max(100000) amount!: number;
  @IsOptional() @IsString() @MaxLength(120) note?: string;
}

export function receiptNo() { return `DEMO-${new Date().toISOString().substring(0, 10).replace(/-/g, '')}-${randomBytes(4).toString('hex').toUpperCase()}`; }

@Injectable()
export class CommerceService {
  constructor(private readonly db: Database, private readonly settings: SettingsService) {}

  async openDraws() {
    const now = new Date();
    const draws = await this.db.lotteryDraw.findMany({
      where: { status: { in: [DrawStatus.SCHEDULED, DrawStatus.DRAFT] }, market: { enabled: true }, tickets: { some: {} } },
      include: { market: true, _count: { select: { tickets: { where: { status: TicketStatus.AVAILABLE } } } } },
      orderBy: { drawDate: 'asc' },
    });
    return draws.map((d) => ({
      id: d.id, marketId: d.marketId, marketName: d.market.nameTh, kind: d.market.kind, drawDate: d.drawDate.toISOString().substring(0, 10),
      opensAt: d.opensAt, closesAt: d.closesAt, salesState: salesState(now, d.opensAt, d.closesAt, d.status), available: d._count.tickets, price: d.market.ticketPrice,
    }));
  }

  async tickets(q: { drawId?: string; number?: string; page?: number; pageSize?: number }) {
    const page = Math.max(1, Number(q.page) || 1), pageSize = Math.min(50, Math.max(1, Number(q.pageSize) || 20));
    const digits = (q.number ?? '').replace(/\D/g, '').substring(0, 6);
    const where: Prisma.DemoTicketWhereInput = {
      status: TicketStatus.AVAILABLE, draw: { status: { in: [DrawStatus.SCHEDULED, DrawStatus.DRAFT] }, market: { enabled: true } },
      ...(q.drawId ? { drawId: q.drawId } : {}), ...(digits ? { number: { contains: digits } } : {}),
    };
    const [total, items] = await this.db.$transaction([
      this.db.demoTicket.count({ where }),
      this.db.demoTicket.findMany({ where, include: { draw: { include: { market: true } } }, orderBy: { number: 'asc' }, skip: (page - 1) * pageSize, take: pageSize }),
    ]);
    return { total, page, pageSize, items: items.map((t) => this.presentTicket(t)) };
  }

  presentTicket(t: Prisma.DemoTicketGetPayload<{ include: { draw: { include: { market: true } } } }>) {
    return {
      id: t.id, number: t.number, set: t.set, price: t.price, status: t.status, drawId: t.drawId,
      drawDate: t.draw.drawDate.toISOString().substring(0, 10), closesAt: t.draw.closesAt, marketId: t.draw.marketId, marketName: t.draw.market.nameTh,
      salesState: salesState(new Date(), t.draw.opensAt, t.draw.closesAt, t.draw.status),
    };
  }

  async ticket(id: string) {
    const t = await this.db.demoTicket.findUnique({ where: { id }, include: { draw: { include: { market: true } } } });
    if (!t) throw new NotFoundException('ไม่พบสลาก');
    return this.presentTicket(t);
  }

  async cart(userId: string) {
    const items = await this.db.cartItem.findMany({ where: { userId }, include: { ticket: { include: { draw: { include: { market: true } } } } }, orderBy: { createdAt: 'asc' } });
    const lines = items.map((i) => {
      const t = this.presentTicket(i.ticket);
      const problem = t.status !== TicketStatus.AVAILABLE ? 'สลากนี้ไม่ว่างแล้ว' : t.salesState !== 'OPEN' ? 'งวดนี้ปิดรับแล้ว' : null;
      return { ...t, problem };
    });
    const user = await this.db.user.findUniqueOrThrow({ where: { id: userId } });
    return { items: lines, count: lines.length, total: lines.reduce((s, l) => s + l.price, 0), balance: user.demoBalance };
  }

  async addToCart(userId: string, ticketId: string) {
    const t = await this.db.demoTicket.findUnique({ where: { id: ticketId }, include: { draw: true } });
    if (!t) throw new NotFoundException('ไม่พบสลาก');
    if (t.status !== TicketStatus.AVAILABLE) throw new ConflictException('สลากนี้ไม่ว่างแล้ว');
    if (salesState(new Date(), t.draw.opensAt, t.draw.closesAt, t.draw.status) !== 'OPEN') throw new ConflictException('งวดนี้ไม่เปิดรับ');
    const max = await this.settings.get<number>('maxTicketsPerOrder');
    if ((await this.db.cartItem.count({ where: { userId } })) >= max) throw new BadRequestException(`ตะกร้าเต็ม (สูงสุด ${max} ใบ)`);
    try { await this.db.cartItem.create({ data: { userId, ticketId } }); } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') throw new ConflictException('สลากนี้อยู่ในตะกร้าแล้ว');
      throw e;
    }
    return this.cart(userId);
  }

  async removeFromCart(userId: string, ticketId: string) {
    await this.db.cartItem.deleteMany({ where: { userId, ticketId } });
    return this.cart(userId);
  }

  /** Atomic demo checkout: locks tickets, deducts demo credits, marks SOLD, writes order + ledger + audit. */
  async checkout(user: AuthUser, ip?: string) {
    if (await this.settings.get<boolean>('maintenanceMode')) throw new ForbiddenException('ระบบอยู่ระหว่างปิดปรับปรุง');
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT id FROM "User" WHERE id = ${user.id} FOR UPDATE`;
      const items = await tx.cartItem.findMany({ where: { userId: user.id }, include: { ticket: { include: { draw: true } } } });
      if (items.length === 0) throw new BadRequestException('ตะกร้าว่าง');
      const now = new Date();
      for (const i of items) {
        if (salesState(now, i.ticket.draw.opensAt, i.ticket.draw.closesAt, i.ticket.draw.status) !== 'OPEN') throw new ConflictException(`งวดของสลาก ${i.ticket.number} ปิดรับแล้ว`);
      }
      const ids = items.map((i) => i.ticketId);
      const sold = await tx.demoTicket.updateMany({ where: { id: { in: ids }, status: TicketStatus.AVAILABLE }, data: { status: TicketStatus.SOLD } });
      if (sold.count !== ids.length) throw new ConflictException('มีสลากบางใบถูกจองไปแล้ว กรุณาตรวจสอบตะกร้า');
      const total = items.reduce((s, i) => s + i.ticket.price, 0);
      const u = await tx.user.findUniqueOrThrow({ where: { id: user.id } });
      if (u.demoBalance < total) throw new BadRequestException(`เครดิตจำลองไม่พอ (คงเหลือ ${u.demoBalance} บาท ต้องการ ${total} บาท)`);
      const after = await tx.user.update({ where: { id: user.id }, data: { demoBalance: { decrement: total } } });
      const order = await tx.order.create({
        data: { receiptNo: receiptNo(), userId: user.id, total, items: { create: items.map((i) => ({ ticketId: i.ticketId, number: i.ticket.number, drawId: i.ticket.drawId, price: i.ticket.price })) } },
        include: { items: true },
      });
      await tx.walletTransaction.create({ data: { userId: user.id, type: WalletTxType.PURCHASE_DEMO, amount: -total, balanceAfter: after.demoBalance, reference: order.receiptNo, note: `ซื้อสลาก ${items.length} ใบ (DEMO)` } });
      await tx.cartItem.deleteMany({ where: { userId: user.id } });
      await tx.notification.create({ data: { userId: user.id, title: 'ยืนยันรายการสำเร็จ (DEMO)', body: `ใบรับ ${order.receiptNo} จำนวน ${items.length} ใบ รวม ${total} บาท (เครดิตจำลอง)`, link: `/app/orders/${order.id}` } });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action: 'CHECKOUT_DEMO', entityType: 'order', entityId: order.id, after: { receiptNo: order.receiptNo, total, tickets: items.map((i) => i.ticket.number) }, ip });
      return order;
    });
  }

  private async attachResults(items: { drawId: string; number: string }[]) {
    const drawIds = [...new Set(items.map((i) => i.drawId))];
    const draws = await this.db.lotteryDraw.findMany({ where: { id: { in: drawIds } }, include: { market: true } });
    const byId = new Map(draws.map((d) => [d.id, d]));
    return (i: { drawId: string; number: string }) => {
      const d = byId.get(i.drawId);
      const published = d?.status === DrawStatus.PUBLISHED;
      return {
        drawDate: d?.drawDate.toISOString().substring(0, 10), marketId: d?.marketId, marketName: d?.market.nameTh, drawStatus: d?.status,
        resultState: published ? 'ANNOUNCED' : d?.status === DrawStatus.CANCELLED ? 'CANCELLED' : 'WAITING',
        matches: published ? matchTicket(i.number, d!.results as Record<string, string>) : [],
      };
    };
  }

  async orders(userId: string, status?: string) {
    const orders = await this.db.order.findMany({
      where: { userId, ...(status && Object.values(OrderStatus).includes(status as OrderStatus) ? { status: status as OrderStatus } : {}) },
      include: { items: true }, orderBy: { createdAt: 'desc' }, take: 100,
    });
    return orders;
  }

  async order(userId: string, id: string, isStaff = false) {
    const o = await this.db.order.findUnique({ where: { id }, include: { items: true, user: { select: { email: true, displayName: true } } } });
    if (!o || (!isStaff && o.userId !== userId)) throw new NotFoundException('ไม่พบรายการ');
    const enrich = await this.attachResults(o.items);
    return { ...o, items: o.items.map((i) => ({ ...i, ...enrich(i) })) };
  }

  async myTickets(userId: string) {
    const items = await this.db.orderItem.findMany({ where: { order: { userId, status: OrderStatus.CONFIRMED_DEMO } }, include: { order: { select: { receiptNo: true, createdAt: true, id: true } } }, orderBy: { order: { createdAt: 'desc' } } });
    const enrich = await this.attachResults(items);
    return items.map((i) => ({ id: i.id, ticketId: i.ticketId, number: i.number, price: i.price, drawId: i.drawId, orderId: i.order.id, receiptNo: i.order.receiptNo, purchasedAt: i.order.createdAt, ...enrich(i) }));
  }

  // ---------- wallet (simulated) ----------
  async wallet(userId: string) {
    const u = await this.db.user.findUniqueOrThrow({ where: { id: userId } });
    const flags = (await this.settings.publicConfig()).flags;
    return { balance: u.demoBalance, currency: 'THB (DEMO credits)', simulated: true, paymentEnabled: flags.PAYMENT_ENABLED };
  }

  transactions(userId: string, type?: string) {
    return this.db.walletTransaction.findMany({
      where: { userId, ...(type && Object.values(WalletTxType).includes(type as WalletTxType) ? { type: type as WalletTxType } : {}) },
      orderBy: { createdAt: 'desc' }, take: 100,
    });
  }

  async topup(user: AuthUser, amount: number, ip?: string) {
    const max = await this.settings.get<number>('maxDemoTopup');
    if (amount > max) throw new BadRequestException(`เติมเครดิตจำลองได้สูงสุด ${max} บาทต่อครั้ง`);
    return this.db.$transaction(async (tx) => {
      const u = await tx.user.update({ where: { id: user.id }, data: { demoBalance: { increment: amount } } });
      const t = await tx.walletTransaction.create({ data: { userId: user.id, type: WalletTxType.TOPUP_DEMO, amount, balanceAfter: u.demoBalance, reference: receiptNo(), note: 'เติมเครดิตจำลอง — ไม่มีการตัดเงินจริง' } });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action: 'TOPUP_DEMO', entityType: 'wallet', entityId: user.id, after: { amount, balance: u.demoBalance }, ip });
      return t;
    });
  }

  /** Withdrawal creates a PENDING simulated request; staff approve/reject. No funds ever leave the system. */
  async withdraw(user: AuthUser, amount: number, ip?: string) {
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT id FROM "User" WHERE id = ${user.id} FOR UPDATE`;
      const cur = await tx.user.findUniqueOrThrow({ where: { id: user.id } });
      if (cur.demoBalance < amount) throw new BadRequestException('เครดิตจำลองไม่พอ');
      const u = await tx.user.update({ where: { id: user.id }, data: { demoBalance: { decrement: amount } } });
      const t = await tx.walletTransaction.create({ data: { userId: user.id, type: WalletTxType.WITHDRAW_DEMO, status: WalletTxStatus.PENDING, amount: -amount, balanceAfter: u.demoBalance, reference: receiptNo(), note: 'คำขอถอนจำลอง — ไม่มีการโอนเงินจริง' } });
      await writeAudit(tx, { actor: user.email, actorId: user.id, action: 'WITHDRAW_DEMO_REQUEST', entityType: 'wallet', entityId: user.id, after: { amount, txId: t.id }, ip });
      return t;
    });
  }

  // ---------- notifications & announcements ----------
  notifications(userId: string) { return this.db.notification.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: 100 }); }
  async markRead(userId: string, id?: string) {
    await this.db.notification.updateMany({ where: { userId, ...(id ? { id } : {}) }, data: { read: true } });
    return { unread: await this.db.notification.count({ where: { userId, read: false } }) };
  }
  announcements() { return this.db.announcement.findMany({ where: { published: true }, orderBy: [{ pinned: 'desc' }, { publishedAt: 'desc' }], take: 50 }); }

  async summary(userId: string) {
    const [u, unread, tickets, nextDraw, latest] = await Promise.all([
      this.db.user.findUniqueOrThrow({ where: { id: userId } }),
      this.db.notification.count({ where: { userId, read: false } }),
      this.db.orderItem.count({ where: { order: { userId, status: OrderStatus.CONFIRMED_DEMO } } }),
      this.openDraws().then((d) => d.find((x) => x.salesState === 'OPEN') ?? d[0] ?? null),
      this.db.lotteryDraw.findMany({ where: { status: DrawStatus.PUBLISHED, market: { enabled: true } }, include: { market: true }, orderBy: { publishedAt: 'desc' }, take: 4 }),
    ]);
    return {
      displayName: u.displayName, kycStatus: u.kycStatus, balance: u.demoBalance, unread, ticketCount: tickets, nextDraw,
      latestResults: latest.map((d) => ({ id: d.id, marketId: d.marketId, marketName: d.market.nameTh, drawDate: d.drawDate.toISOString().substring(0, 10), results: d.results })),
    };
  }
}

/** Generates `count` unique random 6-digit demo tickets for a draw. */
export async function generateTickets(tx: Tx, drawId: string, count: number, price: number) {
  const existing = new Set((await tx.demoTicket.findMany({ where: { drawId }, select: { number: true } })).map((t) => t.number));
  const data: { drawId: string; number: string; price: number }[] = [];
  let guard = 0;
  while (data.length < count && guard++ < count * 20) {
    const n = randomInt(0, 1_000_000).toString().padStart(6, '0');
    if (existing.has(n)) continue;
    existing.add(n);
    data.push({ drawId, number: n, price });
  }
  await tx.demoTicket.createMany({ data, skipDuplicates: true });
  return data.length;
}

@Controller()
export class CommerceController {
  constructor(private readonly svc: CommerceService) {}

  @Public() @Get('catalog/draws') draws() { return this.svc.openDraws(); }
  @Public() @Get('catalog/tickets') tickets(@Query('drawId') drawId?: string, @Query('number') number?: string, @Query('page') page?: number, @Query('pageSize') pageSize?: number) {
    return this.svc.tickets({ drawId, number, page, pageSize });
  }
  @Public() @Get('catalog/tickets/:id') ticket(@Param('id') id: string) { return this.svc.ticket(id); }
  @Public() @Get('announcements') announcements() { return this.svc.announcements(); }

  @Get('me/summary') summary(@CurrentUser() u: AuthUser) { return this.svc.summary(u.id); }
  @Get('cart') cart(@CurrentUser() u: AuthUser) { return this.svc.cart(u.id); }
  @Post('cart') add(@CurrentUser() u: AuthUser, @Body() dto: CartDto) { return this.svc.addToCart(u.id, dto.ticketId); }
  @Delete('cart/:ticketId') remove(@CurrentUser() u: AuthUser, @Param('ticketId') id: string) { return this.svc.removeFromCart(u.id, id); }
  @Post('orders/checkout') checkout(@CurrentUser() u: AuthUser, @ClientIp() ip: string) { return this.svc.checkout(u, ip); }
  @Get('orders') orders(@CurrentUser() u: AuthUser, @Query('status') status?: string) { return this.svc.orders(u.id, status); }
  @Get('orders/:id') order(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.order(u.id, id); }
  @Get('my-tickets') myTickets(@CurrentUser() u: AuthUser) { return this.svc.myTickets(u.id); }
  @Get('wallet') wallet(@CurrentUser() u: AuthUser) { return this.svc.wallet(u.id); }
  @Get('wallet/transactions') txs(@CurrentUser() u: AuthUser, @Query('type') type?: string) { return this.svc.transactions(u.id, type); }
  @Post('wallet/topup') topup(@CurrentUser() u: AuthUser, @Body() dto: AmountDto, @ClientIp() ip: string) { return this.svc.topup(u, dto.amount, ip); }
  @Post('wallet/withdraw') withdraw(@CurrentUser() u: AuthUser, @Body() dto: AmountDto, @ClientIp() ip: string) { return this.svc.withdraw(u, dto.amount, ip); }
  @Get('notifications') notifications(@CurrentUser() u: AuthUser) { return this.svc.notifications(u.id); }
  @Post('notifications/read-all') @HttpCode(200) readAll(@CurrentUser() u: AuthUser) { return this.svc.markRead(u.id); }
  @Post('notifications/:id/read') @HttpCode(200) read(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.markRead(u.id, id); }
}
