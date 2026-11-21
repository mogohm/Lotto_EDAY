# CLAUDE CODE MASTER PROMPT — LOTTO DAY V3 / BLUE WALLET UI

You are the lead Flutter + NestJS + PostgreSQL engineer. **Modify the existing V2/V3 source in place**, preserving the blue digital-wallet design. Do not replace it with a new scaffold. The project is a *non-monetary demo/result-management application*. Do not introduce real-money gambling, wagering, balances, odds, payouts or payments.

## Design tokens — mandatory
- primary `#0078D7`, secondary `#00AEEF`, pale surface `#E8F6FF`, CTA `#FFC700`, navy `#123C63`.
- Thai-first typography Noto Sans Thai fallback; mobile-first, desktop admin sidebar, bottom nav for users, accessible contrast and tap sizes.
- Do not copy any government app logos, trademarks or interface assets.

## Markets and numbers
- Market categories: `DAILY`, `LAO`, `VIETNAM`, `THAI`.
- Daily: create new draw by calendar day; admin enters results or uses cryptographic random **demo generator**; save draft, demo publish and lock.
- Laos/Vietnam/Thailand: admin enters *unverified drafts* with source metadata; do not publish until verified through a separate future authorized backend workflow. The exact official prize format and draw schedule must be confirmed from official sources; do not present all 12 combinations as official categories.
- All markets must have configurable supported digit counts `2,3,4` and positions `front,back,top,bottom`; each enabled combination has a key such as `3:front`. Store numbers as text to keep leading zeroes. Use 12 cells as a demo configuration only, not regulatory truth.
- Draw status: `SCHEDULED`, `DRAFT`, `PUBLISHED`, `CANCELLED` (optionally `AWAITING_REVIEW` in future).
- Audit every draft, status transition and publication. Immutability after publication; revision/correction via separate record.

## Existing implementation
Flutter: `lib/features/lottery/lottery_store.dart`, `lottery_admin_pages.dart`, `lottery_public_page.dart`, routes in `lib/main.dart`, admin menus in `lib/app/app_shell.dart`.
NestJS: `backend/src/*`, `backend/prisma/schema.prisma`. Specification: `docs/LOTTERY_V3_SPEC.md`.

## Next engineering tasks — implement and verify
1. Run `flutter pub get`, `flutter analyze`, `flutter test` and `flutter run -d chrome`. Fix all compiler/runtime issues, preserving the existing V2 routes and functionality.
2. Run `cd backend && npm install && npm run db:generate && npm run typecheck && npm run build`; fix issues. Run PostgreSQL Docker then `npm run db:push` and integration tests against disposable database.
3. Replace Flutter in-memory store with repository abstraction, REST client, auth-aware API states (loading/empty/error), optimistic version handling, error toasts and retries. Keep offline demo mode separately selectable. Never expose admin key in public client.
4. Implement production-grade admin sign-in (OIDC / corporate SSO), HTTP-only session, CSRF mitigation, per-module RBAC (admin, results-editor, reviewer, auditor), MFA and protected API endpoints, rate limiting.
5. Build external-result verification workflow with official source URL, record/time of capture, editor/reviewer separation and publish approval; never infer official results automatically.
6. Market-config admin screen to enable/disable digits/positions for each actual lottery product; configure draw calendars/time zone `Asia/Bangkok` and status cutoffs according to verified source rules.
7. Add responsive admin filters by market, date, status, source, editor, with audit view and CSV read-only report.
8. Add test cases for 0-prefix numbers, input lengths, status transitions, no external demo publishing, no editing after publish, duplicate draw dates, stale version, access control, audit integrity.
9. Provide a single `README` with reproducible commands, actual pass/fail evidence and any unfinished items. Do not claim tests pass unless executed.
10. Keep all financial features permanently disabled in this demo; real-world launch would require separate legal and provider authorization.

## Acceptance criteria
All 4 market types are visible, responsive user result view and admin pages render, 2/3/4-digit position inputs validate, daily demo generate works, draft save works, published demo is immutable, external publishing is blocked, and code passes actual compiler/test checks. No placeholder CRUD links pretending to be completed features.
