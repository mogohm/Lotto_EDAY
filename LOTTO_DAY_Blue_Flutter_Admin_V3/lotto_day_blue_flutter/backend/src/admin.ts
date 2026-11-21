import {
  BadRequestException, Body, ConflictException, Controller, Delete, ForbiddenException, Get, Header, HttpCode, Injectable, NotFoundException, Param, Patch, Post, Query,
} from '@nestjs/common';
import { KycStatus, OrderStatus, Prisma, Role, TicketStatus, UserStatus, WalletTxStatus, WalletTxType } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { Type } from 'class-transformer';
import { IsBoolean, IsEmail, IsIn, IsInt, IsObject, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';
import { PASSWORD_RULE, publicUser } from './auth.controller';
import { AuthUser, ClientIp, CurrentUser, RequirePerms } from './common/auth';
import { auditHash, Database, writeAudit } from './common/database';
import { PERMISSIONS, ROLE_LABEL_TH, ROLE_PERMISSIONS } from './common/permissions';
import { bangkokToday } from './common/rules';
import { SettingsService } from './common/settings.service';
import { generateTickets } from './commerce';

class CreateUserDto {
  @IsEmail() email!: string;
  @IsString() @MinLength(2) @MaxLength(80) displayName!: string;
  @Matches(PASSWORD_RULE, { message: 'รหัสผ่านต้องยาว 8 ตัวขึ้นไป มีทั้งตัวอักษรและตัวเลข' }) password!: string;
  @IsIn(Object.values(Role)) role!: Role;
  @IsOptional() @Matches(/^0\d{8,9}$/) phone?: string;
}
class UpdateUserDto {
  @IsOptional() @IsString() @MinLength(2) @MaxLength(80) displayName?: string;
  @IsOptional() @IsIn(Object.values(Role)) role?: Role;
  @IsOptional() @IsIn(Object.values(UserStatus)) status?: UserStatus;
  @IsOptional() @IsIn(Object.values(KycStatus)) kycStatus?: KycStatus;
  @IsOptional() @Matches(PASSWORD_RULE) resetPassword?: string;
}
class TicketGenDto {
  @IsString() drawId!: string;
  @Type(() => Number) @IsInt() @Min(1) @Max(500) count!: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(10000) price?: number;
}
class TicketStatusDto { @IsIn([TicketStatus.AVAILABLE, TicketStatus.WITHDRAWN]) status!: TicketStatus }
class NoteDto { @IsOptional() @IsString() @MaxLength(300) note?: string }
class AnnouncementDto {
  @IsOptional() @IsString() @MinLength(2) @MaxLength(150) title?: string;
  @IsOptional() @IsString() @MaxLength(5000) body?: string;
  @IsOptional() @IsIn(['NEWS', 'RESULT', 'SYSTEM', 'PROMO']) category?: string;
  @IsOptional() @IsBoolean() pinned?: boolean;
  @IsOptional() @IsBoolean() published?: boolean;
}
class SettingsDto { @IsObject() values!: Record<string, unknown> }

function csv(rows: Record<string, unknown>[], columns: string[]) {
  const esc = (v: unknown) => {
    let s = v instanceof Date ? v.toISOString() : v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v);
    if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`; // CSV formula-injection guard
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return '﻿' + [columns.join(','), ...rows.map((r) => columns.map((c) => esc(r[c])).join(','))].join('\r\n');
}

@Injectable()
export class AdminService {
  constructor(private readonly db: Database) {}

  async dashboard() {
    const today = new Date(`${bangkokToday()}T00:00:00+07:00`);
    const since = new Date(today.getTime() - 13 * 86400_000);
    const [users, usersToday, orders, sales, awaiting, approved, ticketsAvail, ticketsSold, recentOrders, pendingWithdrawals, dailyRows] = await Promise.all([
      this.db.user.count({ where: { role: Role.USER } }),
      this.db.user.count({ where: { role: Role.USER, lastLoginAt: { gte: today } } }),
      this.db.order.count({ where: { status: OrderStatus.CONFIRMED_DEMO } }),
      this.db.order.aggregate({ _sum: { total: true }, where: { status: OrderStatus.CONFIRMED_DEMO } }),
      this.db.lotteryDraw.count({ where: { status: 'AWAITING_REVIEW' } }),
      this.db.lotteryDraw.count({ where: { status: 'APPROVED' } }),
      this.db.demoTicket.count({ where: { status: TicketStatus.AVAILABLE } }),
      this.db.demoTicket.count({ where: { status: TicketStatus.SOLD } }),
      this.db.order.findMany({ take: 6, orderBy: { createdAt: 'desc' }, include: { user: { select: { displayName: true } } } }),
      this.db.walletTransaction.count({ where: { type: WalletTxType.WITHDRAW_DEMO, status: WalletTxStatus.PENDING } }),
      this.db.$queryRaw<{ day: string; total: bigint; count: bigint }[]>`
        SELECT to_char(("createdAt" AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok')::date, 'YYYY-MM-DD') AS day, COALESCE(SUM(total),0)::bigint AS total, COUNT(*)::bigint AS count
        FROM "Order" WHERE status = 'CONFIRMED_DEMO' AND "createdAt" >= ${since} GROUP BY 1 ORDER BY 1`,
    ]);
    const byDay = new Map(dailyRows.map((r) => [r.day, r]));
    const daily = Array.from({ length: 14 }, (_, i) => {
      const d = new Date(since.getTime() + i * 86400_000 + 7 * 3600_000).toISOString().substring(0, 10);
      const r = byDay.get(d);
      return { day: d, total: Number(r?.total ?? 0), count: Number(r?.count ?? 0) };
    });
    return {
      kpi: { demoSalesTotal: sales._sum.total ?? 0, orders, users, usersToday, awaitingReview: awaiting, approved, ticketsAvailable: ticketsAvail, ticketsSold, pendingWithdrawals },
      daily, recentOrders: recentOrders.map((o) => ({ id: o.id, receiptNo: o.receiptNo, total: o.total, status: o.status, createdAt: o.createdAt, user: o.user.displayName })),
    };
  }

  async users(q: { q?: string; role?: string; status?: string; page?: number }) {
    const page = Math.max(1, Number(q.page) || 1);
    const where: Prisma.UserWhereInput = {
      ...(q.q ? { OR: [{ email: { contains: q.q, mode: 'insensitive' } }, { displayName: { contains: q.q, mode: 'insensitive' } }, { phone: { contains: q.q } }] } : {}),
      ...(q.role && Object.values(Role).includes(q.role as Role) ? { role: q.role as Role } : {}),
      ...(q.status && Object.values(UserStatus).includes(q.status as UserStatus) ? { status: q.status as UserStatus } : {}),
    };
    const [total, rows] = await this.db.$transaction([
      this.db.user.count({ where }), this.db.user.findMany({ where, orderBy: { createdAt: 'desc' }, skip: (page - 1) * 50, take: 50 }),
    ]);
    return { total, page, items: rows.map(publicUser) };
  }

  async createUser(dto: CreateUserDto, actor: AuthUser, ip?: string) {
    if ((dto.role === Role.SUPER_ADMIN || dto.role === Role.ADMIN) && actor.role !== Role.SUPER_ADMIN) throw new ForbiddenException('เฉพาะผู้ดูแลสูงสุดเท่านั้นที่สร้างผู้ดูแลได้');
    const email = dto.email.toLowerCase().trim();
    if (await this.db.user.findUnique({ where: { email } })) throw new ConflictException('อีเมลนี้ถูกใช้แล้ว');
    return this.db.$transaction(async (tx) => {
      const u = await tx.user.create({ data: { email, displayName: dto.displayName, phone: dto.phone, role: dto.role, passwordHash: await bcrypt.hash(dto.password, 10) } });
      await writeAudit(tx, { actor: actor.email, actorId: actor.id, action: 'CREATE_USER', entityType: 'user', entityId: u.id, after: { email, role: u.role }, ip });
      return publicUser(u);
    });
  }

  async updateUser(id: string, dto: UpdateUserDto, actor: AuthUser, ip?: string) {
    const before = await this.db.user.findUnique({ where: { id } });
    if (!before) throw new NotFoundException('ไม่พบผู้ใช้');
    if (dto.role !== undefined && dto.role !== before.role) {
      if (!ROLE_PERMISSIONS[actor.role].includes('roles.manage')) throw new ForbiddenException('ไม่มีสิทธิ์เปลี่ยนบทบาท (roles.manage)');
      if (id === actor.id) throw new ForbiddenException('ไม่สามารถเปลี่ยนบทบาทของตนเองได้');
    }
    if (before.role === Role.SUPER_ADMIN && actor.role !== Role.SUPER_ADMIN) throw new ForbiddenException('ไม่สามารถแก้ไขผู้ดูแลสูงสุดได้');
    if (dto.status === UserStatus.SUSPENDED && id === actor.id) throw new ForbiddenException('ไม่สามารถระงับบัญชีตนเองได้');
    return this.db.$transaction(async (tx) => {
      const revoke = dto.status === UserStatus.SUSPENDED || (dto.role !== undefined && dto.role !== before.role) || !!dto.resetPassword;
      const u = await tx.user.update({ where: { id }, data: {
        displayName: dto.displayName, role: dto.role, status: dto.status, kycStatus: dto.kycStatus,
        passwordHash: dto.resetPassword ? await bcrypt.hash(dto.resetPassword, 10) : undefined,
        tokenVersion: revoke ? { increment: 1 } : undefined,
      } });
      await writeAudit(tx, { actor: actor.email, actorId: actor.id, action: 'UPDATE_USER', entityType: 'user', entityId: id, ip,
        before: { displayName: before.displayName, role: before.role, status: before.status, kycStatus: before.kycStatus },
        after: { displayName: u.displayName, role: u.role, status: u.status, kycStatus: u.kycStatus, passwordReset: !!dto.resetPassword } });
      return publicUser(u);
    });
  }

  async tickets(q: { drawId?: string; status?: string; number?: string; page?: number }) {
    const page = Math.max(1, Number(q.page) || 1);
    const where: Prisma.DemoTicketWhereInput = {
      ...(q.drawId ? { drawId: q.drawId } : {}),
      ...(q.status && Object.values(TicketStatus).includes(q.status as TicketStatus) ? { status: q.status as TicketStatus } : {}),
      ...(q.number ? { number: { contains: q.number.replace(/\D/g, '') } } : {}),
    };
    const [total, items] = await this.db.$transaction([
      this.db.demoTicket.count({ where }),
      this.db.demoTicket.findMany({ where, orderBy: { number: 'asc' }, skip: (page - 1) * 50, take: 50, include: { draw: { select: { drawDate: true, marketId: true } } } }),
    ]);
    return { total, page, items };
  }

  async generateTickets(dto: TicketGenDto, actor: AuthUser, ip?: string) {
    return this.db.$transaction(async (tx) => {
      const draw = await tx.lotteryDraw.findUnique({ where: { id: dto.drawId }, include: { market: true } });
      if (!draw) throw new NotFoundException('ไม่พบงวด');
      if (!['SCHEDULED', 'DRAFT'].includes(draw.status)) throw new ConflictException('งวดนี้ปิดการขายแล้ว');
      const n = await generateTickets(tx, draw.id, dto.count, dto.price ?? draw.market.ticketPrice);
      await writeAudit(tx, { actor: actor.email, actorId: actor.id, action: 'GENERATE_TICKETS', entityType: 'draw', entityId: draw.id, after: { count: n }, ip });
      return { created: n };
    });
  }

  async setTicketStatus(id: string, status: TicketStatus, actor: AuthUser, ip?: string) {
    return this.db.$transaction(async (tx) => {
      const t = await tx.demoTicket.findUnique({ where: { id } });
      if (!t) throw new NotFoundException('ไม่พบสลาก');
      if (t.status === TicketStatus.SOLD) throw new ConflictException('สลากที่ขายแล้วแก้สถานะไม่ได้');
      const u = await tx.demoTicket.update({ where: { id }, data: { status } });
      if (status === TicketStatus.WITHDRAWN) await tx.cartItem.deleteMany({ where: { ticketId: id } });
      await writeAudit(tx, { actor: actor.email, actorId: actor.id, action: 'SET_TICKET_STATUS', entityType: 'ticket', entityId: id, before: { status: t.status }, after: { status }, ip });
      return u;
    });
  }

  async orders(q: { q?: string; status?: string; from?: string; to?: string; page?: number }) {
    const page = Math.max(1, Number(q.page) || 1);
    const where: Prisma.OrderWhereInput = {
      ...(q.status && Object.values(OrderStatus).includes(q.status as OrderStatus) ? { status: q.status as OrderStatus } : {}),
      ...(q.q ? { OR: [{ receiptNo: { contains: q.q, mode: 'insensitive' } }, { user: { email: { contains: q.q, mode: 'insensitive' } } }, { items: { some: { number: { contains: q.q } } } }] } : {}),
      ...(q.from || q.to ? { createdAt: { gte: q.from ? new Date(`${q.from}T00:00:00+07:00`) : undefined, lte: q.to ? new Date(`${q.to}T23:59:59+07:00`) : undefined } } : {}),
    };
    const [total, items] = await this.db.$transaction([
      this.db.order.count({ where }),
      this.db.order.findMany({ where, include: { items: true, user: { select: { email: true, displayName: true } } }, orderBy: { createdAt: 'desc' }, skip: (page - 1) * 50, take: 50 }),
    ]);
    return { total, page, items };
  }

  /** Cancels a demo order: releases tickets and refunds demo credits. */
  async cancelOrder(id: string, note: string | undefined, actor: AuthUser, ip?: string) {
    return this.db.$transaction(async (tx) => {
      const o = await tx.order.findUnique({ where: { id }, include: { items: true } });
      if (!o) throw new NotFoundException('ไม่พบรายการ');
      if (o.status !== OrderStatus.CONFIRMED_DEMO) throw new ConflictException('รายการนี้ถูกยกเลิกแล้ว');
      const draws = await tx.lotteryDraw.findMany({ where: { id: { in: o.items.map((i) => i.drawId) } } });
      if (draws.some((d) => d.status === 'PUBLISHED')) throw new ConflictException('ไม่สามารถยกเลิกรายการของงวดที่ประกาศผลแล้ว');
      await tx.order.update({ where: { id }, data: { status: OrderStatus.CANCELLED, cancelNote: note ?? 'ยกเลิกโดยผู้ดูแล' } });
      await tx.demoTicket.updateMany({ where: { id: { in: o.items.map((i) => i.ticketId) } }, data: { status: TicketStatus.AVAILABLE } });
      const u = await tx.user.update({ where: { id: o.userId }, data: { demoBalance: { increment: o.total } } });
      await tx.walletTransaction.create({ data: { userId: o.userId, type: WalletTxType.REFUND_DEMO, amount: o.total, balanceAfter: u.demoBalance, reference: o.receiptNo, note: `คืนเครดิตจำลองจากการยกเลิก ${o.receiptNo}` } });
      await tx.notification.create({ data: { userId: o.userId, title: 'รายการถูกยกเลิก (DEMO)', body: `ใบรับ ${o.receiptNo} ถูกยกเลิก และคืนเครดิตจำลอง ${o.total} บาทแล้ว` } });
      await writeAudit(tx, { actor: actor.email, actorId: actor.id, action: 'CANCEL_ORDER', entityType: 'order', entityId: id, before: { status: o.status, items: o.items.map((i) => i.number) }, after: { status: 'CANCELLED', refund: o.total, note }, ip });
      return { ok: true };
    });
  }

  withdrawals(status?: string) {
    return this.db.walletTransaction.findMany({
      where: { type: WalletTxType.WITHDRAW_DEMO, ...(status && Object.values(WalletTxStatus).includes(status as WalletTxStatus) ? { status: status as WalletTxStatus } : {}) },
      include: { user: { select: { email: true, displayName: true } } }, orderBy: { createdAt: 'desc' }, take: 100,
    });
  }

  async decideWithdrawal(id: string, approve: boolean, actor: AuthUser, ip?: string) {
    return this.db.$transaction(async (tx) => {
      const t = await tx.walletTransaction.findUnique({ where: { id } });
      if (!t || t.type !== WalletTxType.WITHDRAW_DEMO) throw new NotFoundException('ไม่พบคำขอ');
      if (t.status !== WalletTxStatus.PENDING) throw new ConflictException('คำขอนี้ดำเนินการแล้ว');
      await tx.walletTransaction.update({ where: { id }, data: { status: approve ? WalletTxStatus.SUCCESS : WalletTxStatus.REJECTED } });
      if (!approve) {
        const u = await tx.user.update({ where: { id: t.userId }, data: { demoBalance: { increment: -t.amount } } });
        await tx.walletTransaction.create({ data: { userId: t.userId, type: WalletTxType.REFUND_DEMO, amount: -t.amount, balanceAfter: u.demoBalance, reference: t.reference, note: 'คืนเครดิตจำลองจากคำขอถอนที่ถูกปฏิเสธ' } });
      }
      await tx.notification.create({ data: { userId: t.userId, title: approve ? 'คำขอถอนจำลองได้รับอนุมัติ' : 'คำขอถอนจำลองถูกปฏิเสธ', body: 'ระบบสาธิต: ไม่มีการโอนเงินจริง' } });
      await writeAudit(tx, { actor: actor.email, actorId: actor.id, action: approve ? 'APPROVE_WITHDRAW_DEMO' : 'REJECT_WITHDRAW_DEMO', entityType: 'wallet', entityId: id, ip });
      return { ok: true };
    });
  }

  announcementsAll() { return this.db.announcement.findMany({ orderBy: [{ pinned: 'desc' }, { createdAt: 'desc' }] }); }

  async saveAnnouncement(id: string | null, dto: AnnouncementDto, actor: AuthUser, ip?: string) {
    return this.db.$transaction(async (tx) => {
      const before = id ? await tx.announcement.findUnique({ where: { id } }) : null;
      if (id && !before) throw new NotFoundException('ไม่พบประกาศ');
      if (!id && (!dto.title || !dto.body)) throw new BadRequestException('title and body required');
      const publishedAt = dto.published && !before?.published ? new Date() : undefined;
      const a = id
        ? await tx.announcement.update({ where: { id }, data: { ...dto, publishedAt } })
        : await tx.announcement.create({ data: { title: dto.title!, body: dto.body!, category: dto.category, pinned: dto.pinned ?? false, published: dto.published ?? false, publishedAt, createdById: actor.id } });
      await writeAudit(tx, { actor: actor.email, actorId: actor.id, action: id ? 'UPDATE_ANNOUNCEMENT' : 'CREATE_ANNOUNCEMENT', entityType: 'announcement', entityId: a.id, before, after: a, ip });
      return a;
    });
  }

  async deleteAnnouncement(id: string, actor: AuthUser, ip?: string) {
    return this.db.$transaction(async (tx) => {
      const a = await tx.announcement.delete({ where: { id } });
      await writeAudit(tx, { actor: actor.email, actorId: actor.id, action: 'DELETE_ANNOUNCEMENT', entityType: 'announcement', entityId: id, before: a, ip });
      return { ok: true };
    });
  }

  audit(q: { action?: string; entityType?: string; entityId?: string; actor?: string; from?: string; to?: string; take?: number }) {
    return this.db.auditEvent.findMany({
      where: {
        ...(q.action ? { action: q.action } : {}), ...(q.entityType ? { entityType: q.entityType } : {}), ...(q.entityId ? { entityId: q.entityId } : {}),
        ...(q.actor ? { actor: { contains: q.actor, mode: 'insensitive' } } : {}),
        ...(q.from || q.to ? { timestamp: { gte: q.from ? new Date(`${q.from}T00:00:00+07:00`) : undefined, lte: q.to ? new Date(`${q.to}T23:59:59+07:00`) : undefined } } : {}),
      },
      orderBy: { seq: 'desc' }, take: Math.min(Number(q.take) || 200, 1000),
    });
  }

  /** Recomputes the full hash chain. */
  async verifyAudit() {
    const rows = await this.db.auditEvent.findMany({ orderBy: { seq: 'asc' } });
    let prev = '';
    for (const r of rows) {
      const expected = auditHash(prev, { actor: r.actor, action: r.action, entityType: r.entityType, entityId: r.entityId, before: r.before, after: r.after, timestamp: r.timestamp });
      if (r.prevHash !== prev || r.hash !== expected) return { ok: false, checked: rows.length, brokenAt: r.seq, id: r.id };
      prev = r.hash;
    }
    return { ok: true, checked: rows.length, head: prev };
  }

  async report(type: string) {
    switch (type) {
      case 'orders': {
        const rows = await this.db.order.findMany({ include: { user: { select: { email: true } }, items: true }, orderBy: { createdAt: 'desc' }, take: 5000 });
        return csv(rows.map((o) => ({ receiptNo: o.receiptNo, user: o.user.email, total: o.total, status: o.status, tickets: o.items.map((i) => i.number).join(' '), createdAt: o.createdAt })),
          ['receiptNo', 'user', 'total', 'status', 'tickets', 'createdAt']);
      }
      case 'draws': {
        const rows = await this.db.lotteryDraw.findMany({ orderBy: [{ drawDate: 'desc' }], take: 5000 });
        return csv(rows.map((d) => ({ ...d, drawDate: d.drawDate.toISOString().substring(0, 10) })),
          ['marketId', 'drawDate', 'status', 'results', 'sourceName', 'sourceUrl', 'sourceVerified', 'approvedBy', 'publishedAt', 'version']);
      }
      case 'users': {
        const rows = await this.db.user.findMany({ orderBy: { createdAt: 'desc' }, take: 5000 });
        return csv(rows as unknown as Record<string, unknown>[], ['email', 'displayName', 'role', 'status', 'kycStatus', 'demoBalance', 'lastLoginAt', 'createdAt']);
      }
      case 'audit': {
        const rows = await this.db.auditEvent.findMany({ orderBy: { seq: 'desc' }, take: 5000 });
        return csv(rows as unknown as Record<string, unknown>[], ['seq', 'timestamp', 'actor', 'action', 'entityType', 'entityId', 'ip', 'hash']);
      }
      case 'wallet': {
        const rows = await this.db.walletTransaction.findMany({ include: { user: { select: { email: true } } }, orderBy: { createdAt: 'desc' }, take: 5000 });
        return csv(rows.map((t) => ({ ...t, user: t.user.email })), ['createdAt', 'user', 'type', 'status', 'amount', 'balanceAfter', 'reference', 'note']);
      }
      default: throw new NotFoundException('unknown report');
    }
  }

  async reportSummary() {
    const [byMarket, byStatus, wallet] = await Promise.all([
      this.db.$queryRaw<{ marketId: string; tickets: bigint; total: bigint }[]>`
        SELECT d."marketId", COUNT(oi.id)::bigint AS tickets, COALESCE(SUM(oi.price),0)::bigint AS total
        FROM "OrderItem" oi JOIN "Order" o ON o.id = oi."orderId" JOIN "LotteryDraw" d ON d.id = oi."drawId"
        WHERE o.status = 'CONFIRMED_DEMO' GROUP BY d."marketId" ORDER BY 1`,
      this.db.lotteryDraw.groupBy({ by: ['status'], _count: { _all: true } }),
      this.db.walletTransaction.groupBy({ by: ['type'], _sum: { amount: true }, _count: { _all: true } }),
    ]);
    return {
      salesByMarket: byMarket.map((r) => ({ marketId: r.marketId, tickets: Number(r.tickets), total: Number(r.total) })),
      drawsByStatus: byStatus.map((r) => ({ status: r.status, count: r._count._all })),
      walletByType: wallet.map((r) => ({ type: r.type, count: r._count._all, sum: r._sum.amount ?? 0 })),
    };
  }
}

@Controller('admin')
export class AdminController {
  constructor(private readonly svc: AdminService, private readonly settings: SettingsService) {}

  @RequirePerms('dashboard.view') @Get('dashboard') dashboard() { return this.svc.dashboard(); }

  @RequirePerms('users.view') @Get('users') users(@Query('q') q?: string, @Query('role') role?: string, @Query('status') status?: string, @Query('page') page?: number) {
    return this.svc.users({ q, role, status, page });
  }
  @RequirePerms('users.manage') @Post('users') createUser(@CurrentUser() u: AuthUser, @Body() dto: CreateUserDto, @ClientIp() ip: string) { return this.svc.createUser(dto, u, ip); }
  @RequirePerms('users.manage') @Patch('users/:id') updateUser(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: UpdateUserDto, @ClientIp() ip: string) {
    return this.svc.updateUser(id, dto, u, ip);
  }

  @Get('roles') @RequirePerms('dashboard.view')
  roles() {
    return { permissions: PERMISSIONS, roles: Object.values(Role).map((r) => ({ role: r, label: ROLE_LABEL_TH[r], permissions: ROLE_PERMISSIONS[r] })) };
  }

  @RequirePerms('catalog.manage') @Get('tickets') tickets(@Query('drawId') drawId?: string, @Query('status') status?: string, @Query('number') number?: string, @Query('page') page?: number) {
    return this.svc.tickets({ drawId, status, number, page });
  }
  @RequirePerms('catalog.manage') @Post('tickets/generate') gen(@CurrentUser() u: AuthUser, @Body() dto: TicketGenDto, @ClientIp() ip: string) { return this.svc.generateTickets(dto, u, ip); }
  @RequirePerms('catalog.manage') @Patch('tickets/:id') ticketStatus(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: TicketStatusDto, @ClientIp() ip: string) {
    return this.svc.setTicketStatus(id, dto.status, u, ip);
  }

  @RequirePerms('orders.view') @Get('orders') orders(@Query('q') q?: string, @Query('status') status?: string, @Query('from') from?: string, @Query('to') to?: string, @Query('page') page?: number) {
    return this.svc.orders({ q, status, from, to, page });
  }
  @RequirePerms('orders.manage') @Post('orders/:id/cancel') @HttpCode(200) cancel(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: NoteDto, @ClientIp() ip: string) {
    return this.svc.cancelOrder(id, dto.note, u, ip);
  }
  @RequirePerms('orders.view') @Get('withdrawals') withdrawals(@Query('status') status?: string) { return this.svc.withdrawals(status); }
  @RequirePerms('orders.manage') @Post('withdrawals/:id/approve') @HttpCode(200) approveW(@CurrentUser() u: AuthUser, @Param('id') id: string, @ClientIp() ip: string) { return this.svc.decideWithdrawal(id, true, u, ip); }
  @RequirePerms('orders.manage') @Post('withdrawals/:id/reject') @HttpCode(200) rejectW(@CurrentUser() u: AuthUser, @Param('id') id: string, @ClientIp() ip: string) { return this.svc.decideWithdrawal(id, false, u, ip); }

  @RequirePerms('announcements.manage') @Get('announcements') ann() { return this.svc.announcementsAll(); }
  @RequirePerms('announcements.manage') @Post('announcements') createAnn(@CurrentUser() u: AuthUser, @Body() dto: AnnouncementDto, @ClientIp() ip: string) { return this.svc.saveAnnouncement(null, dto, u, ip); }
  @RequirePerms('announcements.manage') @Patch('announcements/:id') updateAnn(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() dto: AnnouncementDto, @ClientIp() ip: string) {
    return this.svc.saveAnnouncement(id, dto, u, ip);
  }
  @RequirePerms('announcements.manage') @Delete('announcements/:id') delAnn(@CurrentUser() u: AuthUser, @Param('id') id: string, @ClientIp() ip: string) { return this.svc.deleteAnnouncement(id, u, ip); }

  @RequirePerms('reports.view') @Get('reports/summary') summary() { return this.svc.reportSummary(); }
  @RequirePerms('reports.view') @Get('reports/:type.csv') @Header('Content-Type', 'text/csv; charset=utf-8')
  report(@Param('type') type: string) { return this.svc.report(type); }

  @RequirePerms('settings.manage') @Get('settings') getSettings() { return this.settings.all(); }
  @RequirePerms('settings.manage') @Patch('settings') patchSettings(@CurrentUser() u: AuthUser, @Body() dto: SettingsDto, @ClientIp() ip: string) { return this.settings.update(dto.values, u, ip); }

  @RequirePerms('audit.view') @Get('audit')
  audit(@Query('action') action?: string, @Query('entityType') entityType?: string, @Query('entityId') entityId?: string, @Query('actor') actor?: string,
    @Query('from') from?: string, @Query('to') to?: string, @Query('take') take?: number) {
    return this.svc.audit({ action, entityType, entityId, actor, from, to, take });
  }
  @RequirePerms('audit.view') @Get('audit/verify') verify() { return this.svc.verifyAudit(); }
}
