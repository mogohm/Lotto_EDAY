import {
  assertExternalSubmittable, assertSeparationOfDuties, bangkokToday, generateDemoResults, matchTicket, missingKeys, nextStatus, RuleError,
  salesState, validateResults, zonedTime,
} from '../../src/common/rules';
import { auditHash, canonicalJson } from '../../src/common/database';
import { hasPermission, ROLE_PERMISSIONS } from '../../src/common/permissions';

const ALL_D = [2, 3, 4];
const ALL_P = ['front', 'back', 'top', 'bottom'];

describe('validateResults', () => {
  it('keeps leading zeros as strings', () => {
    expect(validateResults({ '2:top': '07', '3:front': '004', '4:back': '0000' }, ALL_D, ALL_P)).toEqual({ '2:top': '07', '3:front': '004', '4:back': '0000' });
  });
  it.each([['2:top', '7'], ['3:front', '0040'], ['4:back', '12a4'], ['2:bottom', ' 12'], ['3:top', 123 as unknown as string]])('rejects bad length/chars %s=%s', (k, v) => {
    expect(() => validateResults({ [k]: v }, ALL_D, ALL_P)).toThrow(RuleError);
  });
  it('rejects unknown keys and keys disabled for the market', () => {
    expect(() => validateResults({ '5:top': '12345' }, ALL_D, ALL_P)).toThrow(/unsupported/);
    expect(() => validateResults({ '6:first': '123456' }, ALL_D, ALL_P)).toThrow(/unsupported/);
    expect(() => validateResults({ '4:top': '1234' }, [2, 3], ALL_P)).toThrow(/unsupported/);
    expect(() => validateResults({ '2:front': '12' }, ALL_D, ['top', 'bottom'])).toThrow(/unsupported/);
  });
  it('drops empty values (partial drafts allowed)', () => {
    expect(validateResults({ '2:top': '', '2:bottom': '55' }, ALL_D, ALL_P)).toEqual({ '2:bottom': '55' });
  });
  it('reports missing keys for review', () => {
    expect(missingKeys({ '2:top': '11' }, [2], ['top', 'bottom'])).toEqual(['2:bottom']);
  });
});

describe('generateDemoResults', () => {
  it('fills every enabled combination with the right digit count', () => {
    const r = generateDemoResults(ALL_D, ALL_P);
    expect(Object.keys(r)).toHaveLength(12);
    for (const [k, v] of Object.entries(r)) expect(v).toMatch(new RegExp(`^\\d{${k.split(':')[0]}}$`));
  });
  it('can produce leading zeros', () => {
    expect(generateDemoResults([4], ['top'], () => 0)).toEqual({ '4:top': '0000' });
  });
});

describe('state machine', () => {
  it('follows SCHEDULED → DRAFT → AWAITING_REVIEW → APPROVED → PUBLISHED', () => {
    expect(nextStatus('SCHEDULED', 'SAVE_DRAFT')).toBe('DRAFT');
    expect(nextStatus('DRAFT', 'SUBMIT')).toBe('AWAITING_REVIEW');
    expect(nextStatus('AWAITING_REVIEW', 'APPROVE')).toBe('APPROVED');
    expect(nextStatus('APPROVED', 'PUBLISH')).toBe('PUBLISHED');
    expect(nextStatus('AWAITING_REVIEW', 'REJECT')).toBe('DRAFT');
  });
  it('locks published and cancelled draws', () => {
    for (const a of ['SAVE_DRAFT', 'SUBMIT', 'APPROVE', 'PUBLISH', 'CANCEL', 'REJECT'] as const) {
      expect(() => nextStatus('PUBLISHED', a)).toThrow(RuleError);
      expect(() => nextStatus('CANCELLED', a)).toThrow(RuleError);
    }
  });
  it('cannot skip review', () => {
    expect(() => nextStatus('DRAFT', 'PUBLISH')).toThrow(/cannot PUBLISH/);
    expect(() => nextStatus('DRAFT', 'APPROVE')).toThrow();
  });
});

describe('external result guards', () => {
  it('requires source url, name and capture time', () => {
    expect(() => assertExternalSubmittable(true, {})).toThrow(/URL/);
    expect(() => assertExternalSubmittable(true, { sourceUrl: 'ftp://x' })).toThrow(/URL/);
    expect(() => assertExternalSubmittable(true, { sourceUrl: 'https://x.org' })).toThrow(/publisher/);
    expect(() => assertExternalSubmittable(true, { sourceUrl: 'https://x.org', sourceName: 'X' })).toThrow(/capture/);
    expect(() => assertExternalSubmittable(true, { sourceUrl: 'https://x.org', sourceName: 'X', sourceCapturedAt: new Date() })).not.toThrow();
    expect(() => assertExternalSubmittable(false, {})).not.toThrow();
  });
  it('enforces four-eyes review for external results only', () => {
    expect(() => assertSeparationOfDuties(true, 'u1', 'u1')).toThrow(/different person/);
    expect(() => assertSeparationOfDuties(true, 'u1', 'u2')).not.toThrow();
    expect(() => assertSeparationOfDuties(false, 'u1', 'u1')).not.toThrow();
  });
});

describe('time & sales window', () => {
  it('converts Bangkok local time to UTC', () => {
    expect(zonedTime('2026-11-21', '15:30').toISOString()).toBe('2026-11-21T08:30:00.000Z');
    expect(() => zonedTime('2026-11-21', '25:00')).toThrow();
    expect(() => zonedTime('21/11/2026', '10:00')).toThrow();
  });
  it('computes sales state', () => {
    const o = new Date('2026-11-21T00:00:00Z'), c = new Date('2026-11-21T08:30:00Z');
    expect(salesState(new Date('2026-11-20T23:00:00Z'), o, c, 'SCHEDULED')).toBe('UPCOMING');
    expect(salesState(new Date('2026-11-21T05:00:00Z'), o, c, 'SCHEDULED')).toBe('OPEN');
    expect(salesState(new Date('2026-11-21T08:30:00Z'), o, c, 'SCHEDULED')).toBe('CLOSED');
    expect(salesState(new Date('2026-11-21T05:00:00Z'), o, c, 'AWAITING_REVIEW')).toBe('CLOSED');
  });
  it('bangkokToday rolls over at 17:00 UTC', () => {
    expect(bangkokToday(new Date('2026-11-21T16:59:00Z'))).toBe('2026-11-21');
    expect(bangkokToday(new Date('2026-11-21T17:00:00Z'))).toBe('2026-11-22');
  });
});

describe('matchTicket (demo comparison)', () => {
  const results = { '2:bottom': '56', '3:front': '789', '3:back': '678', '4:top': '0000' };
  it('matches front by prefix and others by suffix', () => {
    expect(matchTicket('789156', results).map((m) => m.key).sort()).toEqual(['2:bottom', '3:front']);
    expect(matchTicket('123678', results).map((m) => m.key)).toEqual(['3:back']);
    expect(matchTicket('110000', results).map((m) => m.key)).toEqual(['4:top']);
    expect(matchTicket('111111', results)).toEqual([]);
  });
  it('rejects non 6-digit input', () => expect(() => matchTicket('12345', results)).toThrow());
});

describe('audit hash chain', () => {
  const base = { actor: 'a', action: 'X', entityType: 't', entityId: '1', before: null, after: { b: 1, a: [1, { d: 2, c: 3 }] }, timestamp: new Date('2026-01-01T00:00:00Z') };
  it('is independent of key order (jsonb reorders keys)', () => {
    expect(auditHash('', base)).toBe(auditHash('', { ...base, after: { a: [1, { c: 3, d: 2 }], b: 1 } }));
    expect(canonicalJson({ b: 1, a: 2 })).toBe('{"a":2,"b":1}');
  });
  it('changes when any field or the previous hash changes', () => {
    const h = auditHash('', base);
    expect(auditHash('x', base)).not.toBe(h);
    expect(auditHash('', { ...base, action: 'Y' })).not.toBe(h);
    expect(auditHash('', { ...base, after: { b: 2 } })).not.toBe(h);
  });
});

describe('RBAC matrix', () => {
  it('separates duties between roles', () => {
    expect(hasPermission('RESULT_EDITOR', 'results.edit')).toBe(true);
    expect(hasPermission('RESULT_EDITOR', 'results.publish')).toBe(false);
    expect(hasPermission('REVIEWER', 'results.review')).toBe(true);
    expect(hasPermission('REVIEWER', 'results.edit')).toBe(false);
    expect(hasPermission('AUDITOR', 'audit.view')).toBe(true);
    expect(hasPermission('AUDITOR', 'users.manage')).toBe(false);
    expect(hasPermission('ADMIN', 'roles.manage')).toBe(false);
    expect(hasPermission('SUPER_ADMIN', 'roles.manage')).toBe(true);
    expect(ROLE_PERMISSIONS.USER).toHaveLength(0);
  });
});
