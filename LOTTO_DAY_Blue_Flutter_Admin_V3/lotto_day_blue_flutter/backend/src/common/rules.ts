/**
 * Pure domain rules (no I/O) — unit tested in test/unit/rules.spec.ts.
 */
import { randomInt } from 'node:crypto';

export const DIGITS = [2, 3, 4] as const;
export const POSITIONS = ['front', 'back', 'top', 'bottom'] as const;
export type Position = (typeof POSITIONS)[number];

export const POSITION_TH: Record<Position, string> = { front: 'หน้า', back: 'หลัง', top: 'บน', bottom: 'ล่าง' };

export type DrawStatusName = 'SCHEDULED' | 'DRAFT' | 'AWAITING_REVIEW' | 'APPROVED' | 'PUBLISHED' | 'CANCELLED';

export class RuleError extends Error {
  constructor(public readonly kind: 'bad_request' | 'conflict' | 'forbidden', message: string) { super(message); }
}

export function resultKey(digits: number, position: string) { return `${digits}:${position}`; }

/** Validates a results map for a market config. Empty values are dropped (drafts may be partial). */
export function validateResults(
  results: Record<string, unknown>,
  allowedDigits: number[],
  allowedPositions: string[],
): Record<string, string> {
  if (!results || typeof results !== 'object' || Array.isArray(results)) throw new RuleError('bad_request', 'results must be an object');
  const clean: Record<string, string> = {};
  for (const [key, raw] of Object.entries(results)) {
    const m = /^(2|3|4):(front|back|top|bottom)$/.exec(key);
    if (!m || !allowedDigits.includes(Number(m[1])) || !allowedPositions.includes(m[2])) {
      throw new RuleError('bad_request', `unsupported result key ${key}`);
    }
    if (raw === null || raw === undefined || raw === '') continue;
    if (typeof raw !== 'string' || !new RegExp(`^[0-9]{${m[1]}}$`).test(raw)) {
      throw new RuleError('bad_request', `invalid number for ${key}: must be exactly ${m[1]} digits`);
    }
    clean[key] = raw;
  }
  return clean;
}

/** Every enabled combination must be filled before review. */
export function missingKeys(results: Record<string, string>, allowedDigits: number[], allowedPositions: string[]) {
  const missing: string[] = [];
  for (const d of allowedDigits) for (const p of allowedPositions) if (!results[resultKey(d, p)]) missing.push(resultKey(d, p));
  return missing;
}

export function generateDemoResults(allowedDigits: number[], allowedPositions: string[], rnd: (max: number) => number = randomInt) {
  const out: Record<string, string> = {};
  for (const d of [...allowedDigits].sort()) for (const p of allowedPositions) {
    out[resultKey(d, p)] = Array.from({ length: d }, () => rnd(10)).join('');
  }
  return out;
}

const EDITABLE: DrawStatusName[] = ['SCHEDULED', 'DRAFT'];
export function canEditResults(status: DrawStatusName) { return EDITABLE.includes(status); }

export type Transition = 'SAVE_DRAFT' | 'SUBMIT' | 'APPROVE' | 'REJECT' | 'PUBLISH' | 'CANCEL';
const TRANSITIONS: Record<Transition, { from: DrawStatusName[]; to: DrawStatusName }> = {
  SAVE_DRAFT: { from: ['SCHEDULED', 'DRAFT'], to: 'DRAFT' },
  SUBMIT: { from: ['DRAFT'], to: 'AWAITING_REVIEW' },
  APPROVE: { from: ['AWAITING_REVIEW'], to: 'APPROVED' },
  REJECT: { from: ['AWAITING_REVIEW', 'APPROVED'], to: 'DRAFT' },
  PUBLISH: { from: ['APPROVED'], to: 'PUBLISHED' },
  CANCEL: { from: ['SCHEDULED', 'DRAFT', 'AWAITING_REVIEW', 'APPROVED'], to: 'CANCELLED' },
};
export function nextStatus(current: DrawStatusName, action: Transition): DrawStatusName {
  const t = TRANSITIONS[action];
  if (!t.from.includes(current)) {
    throw new RuleError('conflict', `cannot ${action} a draw in status ${current}`);
  }
  return t.to;
}

/** External-result workflow guards: source metadata + four-eyes principle. */
export function assertExternalSubmittable(isExternal: boolean, draw: { sourceUrl?: string | null; sourceName?: string | null; sourceCapturedAt?: Date | null }) {
  if (!isExternal) return;
  if (!draw.sourceUrl || !/^https?:\/\//i.test(draw.sourceUrl)) throw new RuleError('bad_request', 'external result requires an official source URL (http/https)');
  if (!draw.sourceName) throw new RuleError('bad_request', 'external result requires the source publisher name');
  if (!draw.sourceCapturedAt) throw new RuleError('bad_request', 'external result requires the source capture time');
}
export function assertSeparationOfDuties(isExternal: boolean, submittedById: string | null | undefined, reviewerId: string) {
  if (isExternal && submittedById && submittedById === reviewerId) {
    throw new RuleError('forbidden', 'reviewer must be a different person from the editor who submitted the external result');
  }
}

/** Sales window for a draw: UPCOMING / OPEN / CLOSED. */
export function salesState(now: Date, opensAt?: Date | null, closesAt?: Date | null, status?: string): 'UPCOMING' | 'OPEN' | 'CLOSED' {
  if (status && status !== 'SCHEDULED' && status !== 'DRAFT') return 'CLOSED';
  if (opensAt && now < opensAt) return 'UPCOMING';
  if (closesAt && now >= closesAt) return 'CLOSED';
  return 'OPEN';
}

/** Converts a calendar day + "HH:mm" in a fixed-offset zone to UTC. Asia/Bangkok is UTC+7, no DST. */
export function zonedTime(day: string, hhmm: string, offsetHours = 7): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new RuleError('bad_request', 'date must be YYYY-MM-DD');
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(hhmm)) throw new RuleError('bad_request', 'time must be HH:mm');
  const sign = offsetHours >= 0 ? '+' : '-';
  const abs = Math.abs(offsetHours).toString().padStart(2, '0');
  const d = new Date(`${day}T${hhmm}:00${sign}${abs}:00`);
  if (Number.isNaN(d.valueOf())) throw new RuleError('bad_request', 'invalid date');
  return d;
}

export function bangkokToday(now = new Date()): string {
  return new Date(now.getTime() + 7 * 3600_000).toISOString().substring(0, 10);
}

/** DEMO comparison of a 6-digit ticket with published 2/3/4-digit result slots. Not a prize claim. */
export function matchTicket(number: string, results: Record<string, string>) {
  if (!/^\d{6}$/.test(number)) throw new RuleError('bad_request', 'ticket number must be 6 digits');
  const matches: { key: string; value: string; label: string }[] = [];
  for (const [key, value] of Object.entries(results)) {
    const [d, pos] = key.split(':');
    const hit = pos === 'front' ? number.startsWith(value) : number.endsWith(value);
    if (hit) matches.push({ key, value, label: `เลข${POSITION_TH[pos as Position] ?? pos} ${d} ตัว` });
  }
  return matches;
}

export function isSixDigits(s: string) { return /^\d{6}$/.test(s); }
