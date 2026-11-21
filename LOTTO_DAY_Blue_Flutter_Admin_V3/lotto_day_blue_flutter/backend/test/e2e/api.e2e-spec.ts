import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Database } from '../../src/common/database';
import { configureApp } from '../../src/main';
import { AppModule } from '../../src/module';
import { DEMO_USER, seed } from '../../src/seed';

const STAFF_PW = 'Admin@1234';
let app: INestApplication;
let db: Database;
const tokens: Record<string, string> = {};
const api = () => request(app.getHttpServer());
const as = (who: string) => ({ Authorization: `Bearer ${tokens[who]}` });

async function login(email: string, password = STAFF_PW) {
  const r = await api().post('/api/v1/auth/login').send({ email, password }).expect(200);
  return r.body.accessToken as string;
}

beforeAll(async () => {
  const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
  app = configureApp(mod.createNestApplication());
  await app.init();
  db = app.get(Database);
  await seed(db);
  for (const r of ['superadmin', 'admin', 'editor', 'reviewer', 'auditor']) tokens[r] = await login(`${r}@lottoday.demo`);
  tokens.user = await login(DEMO_USER.email, DEMO_USER.password);
  // second editor for four-eyes tests
  await api().post('/api/v1/admin/users').set(as('superadmin')).send({ email: 'editor2@lottoday.demo', displayName: 'Editor 2', password: 'Editor@1234', role: 'RESULT_EDITOR' }).expect(201);
  tokens.editor2 = await login('editor2@lottoday.demo', 'Editor@1234');
});
afterAll(async () => { await app?.close(); });

describe('meta & auth', () => {
  it('health + public config with real-money flags locked off', async () => {
    await api().get('/api/v1/health').expect(200);
    const c = await api().get('/api/v1/config').expect(200);
    expect(c.body.flags).toEqual({ DEMO_MODE: true, LIVE_PURCHASE_ENABLED: false, PAYMENT_ENABLED: false, PRIZE_SETTLEMENT_ENABLED: false, OFFICIAL_FEED_ENABLED: false });
  });
  it('rejects bad credentials and missing tokens', async () => {
    await api().post('/api/v1/auth/login').send({ email: DEMO_USER.email, password: 'wrong-pass1' }).expect(401);
    await api().get('/api/v1/auth/me').expect(401);
    await api().get('/api/v1/auth/me').set({ Authorization: 'Bearer garbage' }).expect(401);
  });
  it('registers a new user, validates password strength and duplicate email', async () => {
    await api().post('/api/v1/auth/register').send({ email: 'weak@x.io', password: 'short', displayName: 'Weak' }).expect(400);
    const r = await api().post('/api/v1/auth/register').send({ email: 'new@x.io', password: 'Passw0rd!', displayName: 'New User' }).expect(201);
    expect(r.body.user.role).toBe('USER');
    expect(r.body.user.demoBalance).toBe(0);
    await api().post('/api/v1/auth/register').send({ email: 'new@x.io', password: 'Passw0rd!', displayName: 'Dup' }).expect(400);
  });
  it('me returns role permissions', async () => {
    const r = await api().get('/api/v1/auth/me').set(as('editor')).expect(200);
    expect(r.body.role).toBe('RESULT_EDITOR');
    expect(r.body.permissions).toContain('results.edit');
  });
  it('change password revokes old tokens', async () => {
    const t = (await api().post('/api/v1/auth/register').send({ email: 'pw@x.io', password: 'Passw0rd1', displayName: 'PW' }).expect(201)).body.accessToken;
    const r = await api().post('/api/v1/auth/change-password').set({ Authorization: `Bearer ${t}` }).send({ currentPassword: 'Passw0rd1', newPassword: 'NewPassw0rd' }).expect(200);
    await api().get('/api/v1/auth/me').set({ Authorization: `Bearer ${t}` }).expect(401);
    await api().get('/api/v1/auth/me').set({ Authorization: `Bearer ${r.body.accessToken}` }).expect(200);
  });
});

describe('access control', () => {
  it.each([
    ['user', 'get', '/api/v1/admin/dashboard', 403],
    ['user', 'get', '/api/v1/admin/audit', 403],
    ['auditor', 'get', '/api/v1/admin/audit', 200],
    ['auditor', 'patch', '/api/v1/admin/settings', 403],
    ['editor', 'get', '/api/v1/admin/users', 403],
    ['reviewer', 'post', '/api/v1/admin/lottery/draws', 403],
    ['admin', 'get', '/api/v1/admin/users', 200],
  ])('%s %s %s → %d', async (who, method, url, code) => {
    await (api() as unknown as Record<string, (u: string) => request.Test>)[method](url).set(as(who)).send({}).expect(code);
  });
  it('only roles.manage may change roles; nobody can change their own', async () => {
    const u = (await api().get('/api/v1/admin/users?q=somying').set(as('admin')).expect(200)).body.items[0];
    await api().patch(`/api/v1/admin/users/${u.id}`).set(as('admin')).send({ role: 'AUDITOR' }).expect(403);
    await api().patch(`/api/v1/admin/users/${u.id}`).set(as('admin')).send({ kycStatus: 'VERIFIED' }).expect(200);
    const me = (await api().get('/api/v1/auth/me').set(as('superadmin'))).body;
    await api().patch(`/api/v1/admin/users/${me.id}`).set(as('superadmin')).send({ role: 'USER' }).expect(403);
  });
  it('suspending a user revokes their session', async () => {
    const r = await api().post('/api/v1/auth/register').send({ email: 'sus@x.io', password: 'Passw0rd1', displayName: 'Sus' }).expect(201);
    await api().patch(`/api/v1/admin/users/${r.body.user.id}`).set(as('admin')).send({ status: 'SUSPENDED' }).expect(200);
    await api().get('/api/v1/auth/me').set({ Authorization: `Bearer ${r.body.accessToken}` }).expect(401);
    await api().post('/api/v1/auth/login').send({ email: 'sus@x.io', password: 'Passw0rd1' }).expect(403);
  });
});

describe('lottery markets & draws', () => {
  it('lists the 4 market kinds publicly', async () => {
    const r = await api().get('/api/v1/lottery/markets').expect(200);
    expect(r.body.map((m: { kind: string }) => m.kind).sort()).toEqual(['DAILY', 'LAO', 'THAI', 'VIETNAM']);
  });
  it('updates market config with validation and optimistic version', async () => {
    const m = (await api().get('/api/v1/admin/lottery/markets').set(as('admin'))).body.find((x: { id: string }) => x.id === 'vietnam');
    await api().patch('/api/v1/admin/lottery/markets/vietnam').set(as('admin')).send({ allowedDigits: [5] }).expect(400);
    await api().patch('/api/v1/admin/lottery/markets/vietnam').set(as('admin')).send({ openTime: '18:00', closeTime: '09:00' }).expect(400);
    const u = await api().patch('/api/v1/admin/lottery/markets/vietnam').set(as('admin')).send({ allowedDigits: [2, 3], allowedPositions: ['top', 'bottom'], expectedVersion: m.version }).expect(200);
    expect(u.body.allowedDigits).toEqual([2, 3]);
    await api().patch('/api/v1/admin/lottery/markets/vietnam').set(as('admin')).send({ enabled: true, expectedVersion: m.version }).expect(409);
  });
  it('creates a market; rejects duplicate draws for the same date', async () => {
    await api().post('/api/v1/admin/lottery/markets').set(as('admin')).send({ id: 'lao-star', nameTh: 'หวยลาวสตาร์', kind: 'LAO', allowedDigits: [2, 3, 4], allowedPositions: ['top', 'bottom'] }).expect(201);
    await api().post('/api/v1/admin/lottery/draws').set(as('editor')).send({ marketId: 'lao-star', date: '2030-01-02' }).expect(201);
    await api().post('/api/v1/admin/lottery/draws').set(as('editor')).send({ marketId: 'lao-star', date: '2030-01-02' }).expect(409);
    await api().post('/api/v1/admin/lottery/draws').set(as('editor')).send({ marketId: 'nope', date: '2030-01-02' }).expect(404);
  });
  it('bulk-creates upcoming draws following the weekday calendar', async () => {
    const r = await api().post('/api/v1/admin/lottery/draws/bulk').set(as('editor')).send({ marketId: 'lao-star', days: 7 }).expect(201);
    expect(r.body.created.length).toBe(7);
    const again = await api().post('/api/v1/admin/lottery/draws/bulk').set(as('editor')).send({ marketId: 'lao-star', days: 7 }).expect(201);
    expect(again.body.created).toEqual([]);
  });
});

describe('daily (internal demo) result workflow', () => {
  let id: string;
  let version: number;
  beforeAll(async () => {
    const d = await api().post('/api/v1/admin/lottery/draws').set(as('editor')).send({ marketId: 'daily', date: '2031-05-05', openTime: '08:00', closeTime: '15:00' }).expect(201);
    id = d.body.id; version = d.body.version;
  });
  it('validates 2/3/4 digit inputs and keeps leading zeros', async () => {
    await api().patch(`/api/v1/admin/lottery/draws/${id}/draft`).set(as('editor')).send({ results: { '3:front': '12' }, expectedVersion: String(version) }).expect(400);
    await api().patch(`/api/v1/admin/lottery/draws/${id}/draft`).set(as('editor')).send({ results: { '9:front': '12' }, expectedVersion: String(version) }).expect(400);
    const r = await api().patch(`/api/v1/admin/lottery/draws/${id}/draft`).set(as('editor')).send({ results: { '2:top': '07', '4:back': '0012' }, expectedVersion: String(version) }).expect(200);
    expect(r.body.results).toEqual({ '2:top': '07', '4:back': '0012' });
    expect(r.body.status).toBe('DRAFT');
    version = r.body.version;
  });
  it('rejects stale versions', async () => {
    await api().patch(`/api/v1/admin/lottery/draws/${id}/draft`).set(as('editor')).send({ results: {}, expectedVersion: String(version - 1) }).expect(409);
  });
  it('cannot submit incomplete results; generate-demo fills all 12 slots', async () => {
    await api().post(`/api/v1/admin/lottery/draws/${id}/submit`).set(as('editor')).send({}).expect(400);
    const g = await api().post(`/api/v1/admin/lottery/draws/${id}/generate-demo`).set(as('editor')).expect(200);
    expect(Object.keys(g.body.results)).toHaveLength(12);
  });
  it('reviewer cannot publish before approval; full flow publishes and locks', async () => {
    await api().post(`/api/v1/admin/lottery/draws/${id}/submit`).set(as('editor')).send({}).expect(200);
    await api().post(`/api/v1/admin/lottery/draws/${id}/publish`).set(as('reviewer')).send({}).expect(409);
    await api().post(`/api/v1/admin/lottery/draws/${id}/approve`).set(as('reviewer')).send({ note: 'ok' }).expect(200);
    const p = await api().post(`/api/v1/admin/lottery/draws/${id}/publish`).set(as('reviewer')).send({}).expect(200);
    expect(p.body.status).toBe('PUBLISHED');
    await api().patch(`/api/v1/admin/lottery/draws/${id}/draft`).set(as('editor')).send({ results: {}, expectedVersion: String(p.body.version) }).expect(409);
    await api().post(`/api/v1/admin/lottery/draws/${id}/generate-demo`).set(as('editor')).expect(409);
    await api().post(`/api/v1/admin/lottery/draws/${id}/cancel`).set(as('admin')).send({ note: 'x' }).expect(409);
  });
  it('published results are public and checkable', async () => {
    const pub = await api().get('/api/v1/lottery/published?marketId=daily').expect(200);
    expect(pub.body.find((d: { id: string }) => d.id === id)).toBeTruthy();
    const draw = pub.body.find((d: { id: string }) => d.id === id);
    const r = await api().get(`/api/v1/lottery/check?number=1234${draw.results['2:bottom']}&drawId=${id}`).expect(200);
    expect(r.body.matches.map((m: { key: string }) => m.key)).toContain('2:bottom');
    await api().get(`/api/v1/lottery/check?number=12&drawId=${id}`).expect(400);
  });
  it('legacy V3 publish-demo endpoint still works for daily only (admin)', async () => {
    const d = await api().post('/api/v1/lottery/admin/draws').set(as('admin')).send({ marketId: 'daily', date: '2031-06-06' }).expect(201);
    await api().post(`/api/v1/lottery/admin/draws/${d.body.id}/generate-demo`).set(as('admin')).expect(200);
    const p = await api().post(`/api/v1/lottery/admin/draws/${d.body.id}/publish-demo`).set(as('admin')).expect(200);
    expect(p.body.status).toBe('PUBLISHED');
    await api().post(`/api/v1/lottery/admin/draws/${d.body.id}/publish-demo`).set(as('editor')).expect(403);
  });
});

describe('external (Lao/Vietnam/Thai) verification workflow', () => {
  let id: string;
  beforeAll(async () => {
    id = (await api().post('/api/v1/admin/lottery/draws').set(as('editor')).send({ marketId: 'thai', date: '2031-07-16' }).expect(201)).body.id;
  });
  it('cannot generate random results for external markets', async () => {
    await api().post(`/api/v1/admin/lottery/draws/${id}/generate-demo`).set(as('editor')).expect(403);
  });
  it('cannot use the legacy demo publish for external markets', async () => {
    await api().post(`/api/v1/lottery/admin/draws/${id}/publish-demo`).set(as('admin')).expect(403);
  });
  it('requires source metadata before review', async () => {
    const all = Object.fromEntries([2, 3, 4].flatMap((d) => ['front', 'back', 'top', 'bottom'].map((p) => [`${d}:${p}`, '0'.repeat(d)])));
    const v = (await api().get(`/api/v1/admin/lottery/draws/${id}`).set(as('editor'))).body.version;
    const r = await api().patch(`/api/v1/admin/lottery/draws/${id}/draft`).set(as('editor')).send({ results: all, expectedVersion: String(v) }).expect(200);
    await api().post(`/api/v1/admin/lottery/draws/${id}/submit`).set(as('editor')).send({}).expect(400);
    await api().patch(`/api/v1/admin/lottery/draws/${id}/draft`).set(as('editor')).send({ results: all, sourceUrl: 'javascript:alert(1)', expectedVersion: String(r.body.version) }).expect(400);
    await api().patch(`/api/v1/admin/lottery/draws/${id}/draft`).set(as('editor')).send({
      results: all, sourceName: 'Official publisher', sourceUrl: 'https://example.org/results', sourceCapturedAt: new Date().toISOString(), expectedVersion: String(r.body.version),
    }).expect(200);
    await api().post(`/api/v1/admin/lottery/draws/${id}/submit`).set(as('editor')).send({}).expect(200);
  });
  it('unpublished external results are hidden from the public', async () => {
    const pub = await api().get('/api/v1/lottery/draws?marketId=thai').expect(200);
    const d = pub.body.find((x: { id: string }) => x.id === id);
    expect(d.results).toEqual({});
  });
  it('enforces separation of duties: a submitter with review rights cannot approve their own submission', async () => {
    // admin has both edit+review permissions: submit as admin, then admin approval must fail
    const d2 = (await api().post('/api/v1/admin/lottery/draws').set(as('admin')).send({ marketId: 'lao', date: '2031-07-17' }).expect(201)).body;
    const all = { '2:front': '11', '2:back': '22', '2:top': '33', '2:bottom': '44', '3:front': '111', '3:back': '222', '3:top': '333', '3:bottom': '444', '4:front': '1111', '4:back': '2222', '4:top': '3333', '4:bottom': '4444' };
    await api().patch(`/api/v1/admin/lottery/draws/${d2.id}/draft`).set(as('admin')).send({ results: all, sourceName: 'X', sourceUrl: 'https://example.org', sourceCapturedAt: new Date().toISOString(), expectedVersion: String(d2.version) }).expect(200);
    await api().post(`/api/v1/admin/lottery/draws/${d2.id}/submit`).set(as('admin')).send({}).expect(200);
    await api().post(`/api/v1/admin/lottery/draws/${d2.id}/approve`).set(as('admin')).send({}).expect(403);
    await api().post(`/api/v1/admin/lottery/draws/${d2.id}/approve`).set(as('reviewer')).send({}).expect(200);
  });
  it('reject sends back to draft with reason; then approve + publish marks source verified', async () => {
    await api().post(`/api/v1/admin/lottery/draws/${id}/reject`).set(as('reviewer')).send({}).expect(400);
    const rej = await api().post(`/api/v1/admin/lottery/draws/${id}/reject`).set(as('reviewer')).send({ note: 'URL mismatch' }).expect(200);
    expect(rej.body.status).toBe('DRAFT');
    await api().post(`/api/v1/admin/lottery/draws/${id}/submit`).set(as('editor2')).send({}).expect(200);
    await api().post(`/api/v1/admin/lottery/draws/${id}/approve`).set(as('reviewer')).send({ note: 'checked against source' }).expect(200);
    const p = await api().post(`/api/v1/admin/lottery/draws/${id}/publish`).set(as('reviewer')).send({}).expect(200);
    expect(p.body.sourceVerified).toBe(true);
    expect(p.body.status).toBe('PUBLISHED');
  });
});

describe('demo commerce (simulated credits only)', () => {
  it('browse → cart → checkout deducts demo credits and marks tickets sold', async () => {
    const draws = (await api().get('/api/v1/catalog/draws').expect(200)).body;
    const open = draws.find((d: { salesState: string }) => d.salesState === 'OPEN');
    expect(open).toBeTruthy();
    const page = (await api().get(`/api/v1/catalog/tickets?drawId=${open.id}&pageSize=2`).expect(200)).body;
    expect(page.items).toHaveLength(2);
    const before = (await api().get('/api/v1/wallet').set(as('user'))).body.balance;
    for (const t of page.items) await api().post('/api/v1/cart').set(as('user')).send({ ticketId: t.id }).expect(201);
    await api().post('/api/v1/cart').set(as('user')).send({ ticketId: page.items[0].id }).expect(409);
    const o = await api().post('/api/v1/orders/checkout').set(as('user')).expect(201);
    expect(o.body.receiptNo).toMatch(/^DEMO-/);
    const after = (await api().get('/api/v1/wallet').set(as('user'))).body.balance;
    expect(after).toBe(before - o.body.total);
    await api().post('/api/v1/cart').set(as('user')).send({ ticketId: page.items[0].id }).expect(409);
    const mine = (await api().get('/api/v1/my-tickets').set(as('user')).expect(200)).body;
    expect(mine.some((t: { number: string }) => t.number === page.items[0].number)).toBe(true);
  });
  it('rejects checkout with insufficient demo credits', async () => {
    const r = await api().post('/api/v1/auth/register').send({ email: 'poor@x.io', password: 'Passw0rd1', displayName: 'Poor' }).expect(201);
    const h = { Authorization: `Bearer ${r.body.accessToken}` };
    const t = (await api().get('/api/v1/catalog/tickets?pageSize=1').expect(200)).body.items[0];
    await api().post('/api/v1/cart').set(h).send({ ticketId: t.id }).expect(201);
    await api().post('/api/v1/orders/checkout').set(h).expect(400);
    await api().post('/api/v1/orders/checkout').set(as('user')).expect(400); // empty cart
  });
  it('simulated top-up / withdrawal with admin decision', async () => {
    await api().post('/api/v1/wallet/topup').set(as('user')).send({ amount: 5 }).expect(400);
    await api().post('/api/v1/wallet/topup').set(as('user')).send({ amount: 999999 }).expect(400);
    await api().post('/api/v1/wallet/topup').set(as('user')).send({ amount: 300 }).expect(201);
    const b0 = (await api().get('/api/v1/wallet').set(as('user'))).body.balance;
    const w = await api().post('/api/v1/wallet/withdraw').set(as('user')).send({ amount: 100 }).expect(201);
    expect(w.body.status).toBe('PENDING');
    await api().post(`/api/v1/admin/withdrawals/${w.body.id}/reject`).set(as('admin')).expect(200);
    await api().post(`/api/v1/admin/withdrawals/${w.body.id}/approve`).set(as('admin')).expect(409);
    expect((await api().get('/api/v1/wallet').set(as('user'))).body.balance).toBe(b0);
  });
  it('admin cancel refunds credits and releases tickets', async () => {
    const orders = (await api().get('/api/v1/orders').set(as('user'))).body;
    const latest = orders[0];
    const b0 = (await api().get('/api/v1/wallet').set(as('user'))).body.balance;
    await api().post(`/api/v1/admin/orders/${latest.id}/cancel`).set(as('auditor')).send({}).expect(403);
    await api().post(`/api/v1/admin/orders/${latest.id}/cancel`).set(as('admin')).send({ note: 'test' }).expect(200);
    expect((await api().get('/api/v1/wallet').set(as('user'))).body.balance).toBe(b0 + latest.total);
    const t = (await api().get(`/api/v1/catalog/tickets/${latest.items[0].ticketId}`).expect(200)).body;
    expect(t.status).toBe('AVAILABLE');
  });
  it('closed draws cannot be bought', async () => {
    const d = (await api().post('/api/v1/admin/lottery/draws').set(as('editor')).send({ marketId: 'daily', date: '2020-01-01' }).expect(201)).body;
    await api().post('/api/v1/admin/tickets/generate').set(as('admin')).send({ drawId: d.id, count: 3 }).expect(201);
    const t = (await api().get(`/api/v1/admin/tickets?drawId=${d.id}`).set(as('admin'))).body.items[0];
    await api().post('/api/v1/cart').set(as('user')).send({ ticketId: t.id }).expect(409);
  });
});

describe('settings, reports, announcements, audit', () => {
  it('real-money flags cannot be enabled', async () => {
    await api().patch('/api/v1/admin/settings').set(as('superadmin')).send({ values: { PAYMENT_ENABLED: true } }).expect(403);
    await api().patch('/api/v1/admin/settings').set(as('superadmin')).send({ values: { LIVE_PURCHASE_ENABLED: true } }).expect(403);
    await api().patch('/api/v1/admin/settings').set(as('superadmin')).send({ values: { DEMO_MODE: false } }).expect(403);
    await api().patch('/api/v1/admin/settings').set(as('superadmin')).send({ values: { unknownKey: 1 } }).expect(400);
    const r = await api().patch('/api/v1/admin/settings').set(as('superadmin')).send({ values: { maxTicketsPerOrder: 10 } }).expect(200);
    expect(r.body.maxTicketsPerOrder).toBe(10);
  });
  it('announcement CRUD + public visibility', async () => {
    const a = (await api().post('/api/v1/admin/announcements').set(as('admin')).send({ title: 'ทดสอบ', body: 'เนื้อหา', published: false }).expect(201)).body;
    expect((await api().get('/api/v1/announcements')).body.some((x: { id: string }) => x.id === a.id)).toBe(false);
    await api().patch(`/api/v1/admin/announcements/${a.id}`).set(as('admin')).send({ published: true }).expect(200);
    expect((await api().get('/api/v1/announcements')).body.some((x: { id: string }) => x.id === a.id)).toBe(true);
    await api().delete(`/api/v1/admin/announcements/${a.id}`).set(as('admin')).expect(200);
  });
  it('dashboard + CSV reports', async () => {
    const d = await api().get('/api/v1/admin/dashboard').set(as('auditor')).expect(200);
    expect(d.body.daily).toHaveLength(14);
    expect(d.body.kpi.orders).toBeGreaterThan(0);
    const csv = await api().get('/api/v1/admin/reports/orders.csv').set(as('auditor')).expect(200);
    expect(csv.headers['content-type']).toMatch(/text\/csv/);
    expect(csv.text).toContain('receiptNo,user,total');
    await api().get('/api/v1/admin/reports/nope.csv').set(as('auditor')).expect(404);
    await api().get('/api/v1/admin/reports/summary').set(as('auditor')).expect(200);
  });
  it('every mutation is audited and the hash chain verifies', async () => {
    const a = (await api().get('/api/v1/admin/audit?entityType=draw&take=500').set(as('auditor')).expect(200)).body;
    const actions = new Set(a.map((e: { action: string }) => e.action));
    for (const x of ['CREATE_DRAW', 'SAVE_DRAFT', 'GENERATE_DEMO', 'SUBMIT', 'APPROVE', 'REJECT', 'PUBLISH']) expect(actions).toContain(x);
    const v = await api().get('/api/v1/admin/audit/verify').set(as('auditor')).expect(200);
    expect(v.body.ok).toBe(true);
    expect(v.body.checked).toBeGreaterThan(20);
  });
  it('tampering with an audit row is detected', async () => {
    const row = await db.auditEvent.findFirstOrThrow({ where: { action: 'PUBLISH' } });
    await db.auditEvent.update({ where: { id: row.id }, data: { actor: 'evil@x.io' } });
    const v = await api().get('/api/v1/admin/audit/verify').set(as('auditor')).expect(200);
    expect(v.body.ok).toBe(false);
    expect(v.body.brokenAt).toBe(row.seq);
    await db.auditEvent.update({ where: { id: row.id }, data: { actor: row.actor } });
    expect((await api().get('/api/v1/admin/audit/verify').set(as('auditor'))).body.ok).toBe(true);
  });
});
