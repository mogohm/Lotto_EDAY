# LOTTO DAY V3 — Lottery Management Specification

## Scope
Four configurable categories: DAILY (admin enters or generates simulated results), LAO, VIETNAM, THAI (external results must be validated against their respective authorized publisher before official publication). All number values are strings. These markets are placeholders/configurations; actual official result formats, schedules and permissible categories must be verified before production.

## Results matrix (configurable)
| Digit length | FRONT | BACK | TOP | BOTTOM |
|---|---|---|---|---|
| 2 | `2:front` | `2:back` | `2:top` | `2:bottom` |
| 3 | `3:front` | `3:back` | `3:top` | `3:bottom` |
| 4 | `4:front` | `4:back` | `4:top` | `4:bottom` |

Position names are logical display labels; **do not assume all combinations exist for official Thai/Lao/Vietnamese lottery programs**. Per-market and per-product enable/disable must be configurable after validating official rules.

## Admin pages implemented in Flutter
- `/admin/lottery`: list of categories, configured digit lengths and positions.
- `/admin/lottery/draws/:marketId`: create draws (one per market/calendar date), list status.
- `/admin/lottery/result/:drawId`: enter 2/3/4 digit results by position, save draft, generate random **DEMO ONLY** results for DAILY, publish **DEMO ONLY** daily results.
- `/admin/lottery/audit`: in-memory demo action history.
- `/app/markets`: public **DEMO** results view. External official results are never published by the Flutter demo.

## Recommended production architecture
Flutter UI -> authenticated NestJS REST API -> PostgreSQL (Prisma) -> audit storage. UI demo currently uses in-memory `LotteryDemoStore`; the NestJS demo API is separate. Claude Code must implement dependency-injected repositories and wire REST API before deployment, without embedding admin keys in Flutter web. Use an identity provider and server-side HttpOnly session, MFA for admin, per-action RBAC, CSRF protection when cookie-based, rate limiting, source attribution, two-person review for external results, server-generated immutable audit, idempotency/concurrency controls, access logs and monitoring.

## State machine
`SCHEDULED -> DRAFT -> PUBLISHED` or `CANCELLED`; published data is locked. Corrections to published results require **a new revision with explicit correction audit** and an approval flow, rather than overwriting old result data. Current demo does not implement corrections.

## API (NestJS demo backend)
- `GET /api/v1/lottery/markets`
- `GET /api/v1/lottery/draws?marketId=daily`
- `GET /api/v1/lottery/published?marketId=daily`
- `POST /api/v1/lottery/admin/seed`
- `POST /api/v1/lottery/admin/draws` `{ "marketId":"daily", "date":"2026-11-21" }`
- `PATCH /api/v1/lottery/admin/draws/:id/draft` `{ "results":{"2:top":"07","3:front":"004"}, "sourceNote":"demo", "expectedVersion":"1" }`
- `POST /api/v1/lottery/admin/draws/:id/generate-demo`
- `POST /api/v1/lottery/admin/draws/:id/publish-demo`
- `GET /api/v1/lottery/admin/audit`

All demo write endpoints require `x-demo-admin-key` configured via `ADMIN_DEMO_KEY`; **this is a local-only demo mechanism and must not be used for production**, cannot be embedded in the client app, and is disabled when `NODE_ENV=production`. API listens on localhost only. To make a production platform, replace demo mechanism with actual admin authentication and authorization.

## Do not build into this demo
No account balances, wager acceptance, bet slips, betting odds, payouts, real-money settlement, payment providers, prize disbursement or arbitrary external lottery result publication. Any such extension must only be pursued after jurisdiction-specific authorization and a compliance/security review.

## Backend boot locally
1. `cd backend && cp .env.example .env` and replace admin demo key with your own secret.
2. `docker compose up -d` (local PostgreSQL)
3. `npm install && npm run db:generate && npm run db:push`
4. `npm run dev`
5. Seed using a local curl request with `x-demo-admin-key` header. Never commit `.env`.

## QA scenarios
- Digits 2/3/4 accept leading zeros, reject non-digits / incorrect lengths.
- Missing fields allowed in drafts; unknown keys rejected.
- Cannot duplicate market/date draw.
- Cannot generate an external lottery result.
- Cannot publish external result through demo endpoint.
- Cannot edit a published demo draw.
- Concurrent writes reject stale `expectedVersion`.
- All mutations persist audit record within the same database transaction.
- Daily results are explicitly labeled DEMO in admin/public screens.

---

## V3.1 implementation update (2026-11-21)
The in-memory UI demo has been replaced by the real stack (Flutter → NestJS → PostgreSQL). Changes against the sections above:

- **State machine** now `SCHEDULED → DRAFT → AWAITING_REVIEW → APPROVED → PUBLISHED` (+ `CANCELLED`). Reject returns to `DRAFT` with a mandatory note.
- **External results** (LAO/VIETNAM/THAI) can be published only after: all enabled slots filled, source name + http(s) URL + capture time recorded, approval by a *different* user with `results.review`, then publish by `results.publish`. `sourceVerified` is set on approval.
- **Auth**: the `x-demo-admin-key` mechanism is retired; every write endpoint (including the legacy `/lottery/admin/*` routes) requires a JWT and role permissions (see `backend/src/common/permissions.ts`).
- **Draw schedule**: each draw has `opensAt`/`closesAt` (Asia/Bangkok, UTC+7) derived from the market config or set per draw; `salesState` = UPCOMING / OPEN / CLOSED.
- **Market config** is editable (digits, positions, times, weekdays, price, enabled) with optimistic versioning; additional markets of the 4 kinds can be created.
- **Audit**: append-only, SHA-256 hash chain (`prevHash`/`hash`, canonical JSON), verified by `GET /api/v1/admin/audit/verify`.
- Full endpoint list: see the project `README.md`.
