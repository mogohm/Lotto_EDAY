# LOTTO DAY V3 — Blue Wallet Full-Stack Demo

Flutter Web (responsive mobile + desktop) · NestJS · PostgreSQL · Prisma

ระบบสาธิตจัดการหวย 4 ประเภท (รายวัน / ลาว / เวียดนาม / ไทย) พร้อมร้านสลากจำลอง กระเป๋าเครดิตจำลอง และหลังบ้านครบทุกเมนู
**ไม่มีการซื้อขายหรือชำระเงินจริง** — real-money flags are hard-locked off in the API.

> Independent blue-wallet-inspired design (`#0078D7` `#00AEEF` `#E8F6FF` `#FFC700` + navy `#123C63`). Not an official app of any agency.

---

## Run everything with one command

```bash
cp .env.example .env          # first time only; edit JWT_SECRET / SEED_STAFF_PASSWORD
docker compose up --build     # → http://localhost:8080
```

The `app` container runs `prisma migrate deploy` → idempotent seed → API, and serves the Flutter web build from the same origin.

### Without Docker (Windows/macOS/Linux, Node 22 + Flutter 3.50)

```bash
flutter build web --release --no-web-resources-cdn      # from the project root
cd backend && npm install && npm run build
npm run dev:embedded       # real PostgreSQL via embedded-postgres (data in backend/.pgdata) + migrate + seed + API
# → http://localhost:3000   (API at /api/v1)
```

For Flutter hot-reload against that API: `flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1`

## Demo accounts (seed)

| Role | Email | Password |
|---|---|---|
| Member (สมชาย ใจดี) | `user@lottoday.demo` | `User@1234` |
| Super admin | `superadmin@lottoday.demo` | `SEED_STAFF_PASSWORD` (default `Admin@1234`) |
| Admin | `admin@lottoday.demo` | 〃 |
| Result editor | `editor@lottoday.demo` | 〃 |
| Reviewer / approver | `reviewer@lottoday.demo` | 〃 |
| Auditor (read-only) | `auditor@lottoday.demo` | 〃 |

## Features

**User app** (`/app/...`, bottom nav on mobile, navigation rail on desktop): welcome / login / register (age + consent), home wallet header with next draw & yellow CTA, ticket catalog (search, paging, sticky cart bar), ticket detail, cart & demo checkout with receipt, my tickets with automatic result matching, transaction history (all/success/pending), simulated wallet (top-up, withdrawal request), results check (4 markets, big-number card, check-my-number), results history, notifications, news, profile / edit profile / change password / help / about.

**Admin** (`/admin/...`, navy sidebar, drawer on mobile, menu filtered by permission): dashboard KPIs + 14-day chart + task queue; users (search/filter, role/status/KYC, reset password, create staff); tickets per draw (generate, withdraw/restore); lottery markets (create, enable/disable, digits 2/3/4, positions หน้า/หลัง/บน/ล่าง, open/close/result time, weekdays, price); draws (create with open/close time, 7-day bulk by calendar, status filter, cancel); **result workflow** (draft → submit → approve/reject → publish, daily DEMO random generator, external source name/URL/capture time, four-eyes rule, immutable after publish, per-draw audit trail); review queue with market/status/date filters; orders (search, cancel+refund) and withdrawal approvals; announcements CRUD; reports + CSV export (orders/draws/users/wallet/audit); RBAC matrix; settings (real-money flags locked); audit log with filters, hash-chain verification and CSV.

**Backend**: JWT bearer auth with token-version revocation (password change / suspension / role change), bcrypt, per-route permissions (`SUPER_ADMIN, ADMIN, RESULT_EDITOR, REVIEWER, AUDITOR, USER`), global rate limit + stricter auth limits, Helmet, validation with whitelist, optimistic concurrency (`expectedVersion`) + row locks, append-only SHA-256 hash-chained audit log written in the same transaction as every mutation, Prisma migrations, idempotent seed.

### Result workflow rules
- `SCHEDULED → DRAFT → AWAITING_REVIEW → APPROVED → PUBLISHED` (or `CANCELLED` before publish). Published draws are locked.
- All configured slots must be filled before review; numbers are strings (leading zeros kept), exact length per digit count.
- DAILY: admin enters or generates crypto-random DEMO results; the legacy one-shot `publish-demo` still works (admin only).
- LAO / VIETNAM / THAI: random generation forbidden; source name + http(s) URL + capture time required to submit; approver must differ from submitter; publish requires reviewer source verification. Unpublished results are never exposed publicly.

## API (prefix `/api/v1`)

Public: `GET health, config, lottery/markets, lottery/draws, lottery/published, lottery/check, catalog/draws, catalog/tickets[/:id], announcements` · Auth: `POST auth/login, auth/register, auth/change-password, auth/logout-all`, `GET/PATCH auth/me`
Member: `GET me/summary, cart, orders[/:id], my-tickets, wallet, wallet/transactions, notifications` · `POST cart, orders/checkout, wallet/topup, wallet/withdraw, notifications/read-all, notifications/:id/read` · `DELETE cart/:ticketId`
Admin lottery: `GET/POST admin/lottery/markets`, `PATCH admin/lottery/markets/:id`, `GET/POST admin/lottery/draws`, `POST admin/lottery/draws/bulk`, `GET admin/lottery/draws/:id`, `PATCH …/:id/schedule`, `PATCH …/:id/draft`, `POST …/:id/{generate-demo,submit,approve,reject,publish,cancel}`
Admin other: `GET admin/dashboard, admin/roles, admin/users, admin/tickets, admin/orders, admin/withdrawals, admin/announcements, admin/reports/summary, admin/reports/{orders,draws,users,wallet,audit}.csv, admin/settings, admin/audit, admin/audit/verify` + corresponding `POST/PATCH/DELETE`.
Legacy V3 routes kept: `POST lottery/admin/{seed,draws}`, `PATCH lottery/admin/draws/:id/draft`, `POST lottery/admin/draws/:id/{generate-demo,publish-demo}` (now JWT + RBAC instead of the local demo key).

## Tests (all executed in this repo on 2026-11-21)

| Suite | Command | Result |
|---|---|---|
| Backend typecheck + build | `cd backend && npm run typecheck && npm run build` | ✅ pass |
| Backend unit (rules, state machine, RBAC, audit hash) | `npm run test:unit` | ✅ 24/24 |
| Backend API e2e (real PostgreSQL via embedded-postgres) | `npm run test:e2e` | ✅ 40/40 |
| Flutter static analysis | `flutter analyze` | ✅ no issues |
| Flutter unit + widget (incl. original V3 store tests) | `flutter test` | ✅ 26/26 |
| Flutter integration (real app in Chrome ↔ real API ↔ real DB) | see below | ✅ pass |
| Flutter web release build | `flutter build web --release --no-web-resources-cdn` | ✅ pass |

Integration test (backend running with seed data, ChromeDriver matching your Chrome on port 4444):
```bash
chromedriver --port=4444 &
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
  -d chrome --web-port 8080 --headless --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

Covered: leading zeros, input length, unknown keys, all status transitions, no external random/demo publish, no edit after publish, duplicate draw dates, stale versions, RBAC per role, four-eyes review, token revocation, rate limiting, insufficient demo credit, closed sales window, order cancel/refund, real-money flags locked, CSV, audit completeness + tamper detection.

## Deployment (Fly.io)

`fly.toml` + `Dockerfile` (multi-stage: Flutter SDK → web build; Node → API; slim runtime). Secrets: `DATABASE_URL` (from `fly postgres attach`), `JWT_SECRET`, `SEED_STAFF_PASSWORD`.
```bash
fly deploy --remote-only
```

## Not finished / out of scope (honest list)
- OIDC/SSO, HttpOnly cookie sessions + CSRF, MFA/OTP for staff (current: JWT bearer in local storage, token revocation, rate limits).
- Official external result feeds (none integrated; results are entered manually and verified by a second person).
- Correction/revision flow for already-published results (currently immutable; no correction records yet).
- Real KYC provider, real payments, prize settlement — intentionally disabled; require legal authorisation.
- Offline demo mode toggle in the UI (the legacy in-memory `LotteryDemoStore`/`DemoStore` remain in code and tests but are not wired to screens).
- English UI translations (Thai only; `intl` + locales configured).
- Bundled Noto Sans Thai font (web uses Flutter's fallback font download).
- Screenshot-diff responsive tests (layout verified by widget tests at 390px and 1280–1440px plus manual screenshots).

See `docs/LOTTERY_V3_SPEC.md` for the domain specification.
