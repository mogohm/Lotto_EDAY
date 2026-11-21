import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';
import { createHash } from 'node:crypto';

export type Tx = Prisma.TransactionClient;

@Injectable()
export class Database extends PrismaClient implements OnModuleDestroy {
  async onModuleDestroy() { await this.$disconnect(); }
}

export interface AuditInput {
  actor: string;
  actorId?: string | null;
  action: string;
  entityType: string;
  entityId: string;
  before?: unknown;
  after?: unknown;
  ip?: string | null;
}

const AUDIT_LOCK = 774411;

/** Deterministic JSON (sorted keys) — jsonb does not preserve key order. */
export function canonicalJson(v: unknown): string {
  if (v === null || v === undefined) return 'null';
  if (Array.isArray(v)) return `[${v.map(canonicalJson).join(',')}]`;
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    return `{${Object.keys(o).sort().filter((k) => o[k] !== undefined).map((k) => `${JSON.stringify(k)}:${canonicalJson(o[k])}`).join(',')}}`;
  }
  return JSON.stringify(v);
}

export function auditHash(prevHash: string, e: { actor: string; action: string; entityType: string; entityId: string; before: unknown; after: unknown; timestamp: Date }) {
  const payload = canonicalJson([prevHash, e.actor, e.action, e.entityType, e.entityId, e.before ?? null, e.after ?? null, e.timestamp.toISOString()]);
  return createHash('sha256').update(payload).digest('hex');
}

/** Appends a hash-chained audit row inside the caller's transaction (serialised by an advisory lock). */
export async function writeAudit(tx: Tx, input: AuditInput) {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(${AUDIT_LOCK})`;
  const last = await tx.auditEvent.findFirst({ orderBy: { seq: 'desc' }, select: { hash: true } });
  const prevHash = last?.hash ?? '';
  const timestamp = new Date();
  const before = (input.before ?? null) as Prisma.InputJsonValue | null;
  const after = (input.after ?? null) as Prisma.InputJsonValue | null;
  // Normalise through JSON so the stored JSON and the hashed JSON are identical.
  const b = before === null ? null : JSON.parse(JSON.stringify(before));
  const a = after === null ? null : JSON.parse(JSON.stringify(after));
  const hash = auditHash(prevHash, { ...input, before: b, after: a, timestamp });
  return tx.auditEvent.create({
    data: {
      actor: input.actor, actorId: input.actorId ?? null, action: input.action, entityType: input.entityType,
      entityId: input.entityId, before: b ?? Prisma.JsonNull, after: a ?? Prisma.JsonNull, ip: input.ip ?? null,
      prevHash, hash, timestamp,
    },
  });
}
