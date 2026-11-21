# LOTTO DAY — Claude Code Master Implementation Prompt V2 (Blue Wallet UI)

You are a senior Flutter architect, product designer, backend architect, security engineer, and QA lead. Build an original, responsive digital lottery information and **licensed-only ticket storefront** application named LOTTO DAY. The design should be inspired by the clear information hierarchy and friendliness of Thai mobile wallet applications, but must NOT copy Paotang branding, trademark, icons, layouts pixel-for-pixel, or claim GLO affiliation.

## CRITICAL SCOPE / SAFETY GATES
- Deliver a FULLY FUNCTIONAL DEMO with seeded test data. Default all real-money transactions, wagering, settlements, prize payouts, deposits, withdrawals, and actual ticket purchase capabilities to **disabled**. Do not create an unauthorized gambling operation.
- Public result lookup, announcements, simulated ticket catalog, demo checkout, profile and analytics can be fully functional without real payments.
- Any live ticket inventory, orders, identity verification, payments, or prize claims MUST be integrated through documented authorized providers and only after legal/contractual approvals. Never invent provider endpoints or pretend demo inventory represents real ownership.
- Include explicit DEMO labeling on simulated screens, receipts and records; separate demo environment from any production records. No artificial prize outcomes or misrepresentation of official results. Require verified official feeds before publishing real results.
- Include age gates, configurable jurisdiction restrictions, KYC states, privacy consent, user spending limits where applicable, voluntary exclusion, rate limits, antifraud and immutable audit logs. Store no raw sensitive KYC scans in logs.

## 1. PRIMARY GOAL
- One Flutter repository supporting responsive Flutter Web mobile/tablet/desktop and preserving portability to Android/iOS.
- Two segregated experiences: user app (`/app/...`) and admin portal (`/admin/...`), each with role-based authorization and separate shells.
- Excellent Android/iOS browser rendering; support installable PWA with offline shell (not offline financial operations), responsive viewports and safe areas.
- Thai UI by default, English i18n infrastructure.
- All flows clickable and testable end-to-end using mock adapters, seed data, and automated tests.

## 2. BRAND & DESIGN SYSTEM
Brand: LOTTO DAY, original ticket-shaped icon; NO government logos or borrowed app assets.
Colors: primary #0078D7 (deep wallet blue), secondary #00AEEF (sky blue), surface #E8F6FF (light icy blue), accent #FFC700 (yellow CTAs), navy #123C63, white #FFFFFF, page background #F4FAFF, main text #183153, border #D9EAF8, success #16835C, error #C93B50. Use contrast-compliant shades.
Typography: Noto Sans Thai with dynamic text scaling. 8px spacing system. Cards 18px radius, buttons 14px radius, 48px minimum touch targets, subtle shadows. Light theme by default and dark-ready tokens.
Mobile user layout: wallet-like blue gradient header, white floating rounded panels, yellow main action button, blue active tab state, airy card grids and a light geometric blue background; 360/390/430px baseline with sticky five-tab navigation (Home, Browse, My Tickets, Results, Profile) and floating cart badge where appropriate. Desktop user layout: top/side nav and max content width 1200px. Admin: navy #123C63 sidebar with vivid-blue selected state + blue header bar; white KPI cards and sky-blue chart accents; collapsible on tablet, drawer on mobile; responsive tables switch to data cards.
Never use color alone for status. Accessible labels, keyboard navigation, visible focus states, clear loading, skeleton, error and empty states.

## 3. USER EXPERIENCE / ROUTES
- /welcome — intro, product scope, demo labeling
- /auth/login, /auth/register, /auth/otp — passwordless demo OTP mechanism ONLY; never expose real OTP in production
- /auth/verification — age/identity verification status and privacy notices; no production KYC until verified provider connected
- /app/home — greeting, current draw, deadline as sourced/configured, quick actions, notices, results teaser
- /app/catalog — searchable authorized/dummy ticket inventory, 6-digit number input, multi-filter chips, availability statuses, paging
- /app/ticket/:id — ticket detail, issuer/authorization status, draw date, price, clear DEMO mode
- /app/cart — demo items, counts, totals, errors on expired/unavailable entries
- /app/checkout — demo-only checkout, no real charges, confirmation and simulated receipt ID
- /app/my-tickets — filter by draw/order status, demo receipt detail and evidence status
- /app/orders/:id — transparent status timeline and support reference
- /app/results — results grouped by draw; explicit official feed source + timestamp; sample results labeled DEMO
- /app/check — enter ticket number to compare with a draw; avoid fabricated claims
- /app/notifications — notice center
- /app/profile — contact details, KYC status, personal settings, privacy/export requests
- /app/security — account sessions, log out all devices, MFA placeholder
- /app/responsible-use — age restriction, help, spend/time limit placeholders, exclusion
- /app/help — FAQ and support tickets
- /legal/terms, /legal/privacy, /legal/disclaimer

## 4. ADMIN EXPERIENCE / ROUTES
- /admin/login — separate login flow, role and MFA check
- /admin — executive dashboard: demo KPI cards (orders, users, pending verification, reconciliation), visual charts and activity feed
- /admin/users — advanced search/filter, user profile, verification status, permitted lock/unlock actions
- /admin/catalog — manage sample catalog, draw cycles, stock states; forbid uncontrolled edits to finalized ownership
- /admin/orders — searchable order table, state timeline, export and exception review
- /admin/payments — reconciliation UI (demo data); provider integration disabled until authorized
- /admin/results — staged import, validation, two-person approval, publication log; no invented official results
- /admin/content — announcements, banners, FAQ
- /admin/reports — date filters, CSV exports, user/draw breakdown
- /admin/support — support queue and notes
- /admin/responsible-use — compliance flags, exclusion controls, configurable limits
- /admin/access — RBAC roles and permissions
- /admin/audit — filterable immutable audit events
- /admin/settings — product config, feature flags, security status and integration connectivity
Admin roles: super_admin, operations, finance, support, auditor, compliance; least-privilege, explicit permission checks on backend.

## 5. TECHNICAL ARCHITECTURE
Client: Flutter latest stable; Dart; Material 3 customized theme; go_router for declarative routes and deep-links; flutter_riverpod for state/DI; dio or http for network; freezed/json_serializable for typed DTOs (choose compatible maintained versions and lock dependencies). Use intl and flutter_localizations, fl_chart or equivalent accessible charting.
Backend preference: NestJS + TypeScript with PostgreSQL 16+ and Prisma ORM; Redis optional (rate limiting / ephemeral sessions), object storage via abstraction, OpenAPI 3 with generated client contract if practical. The backend is included as a separate folder, not simulated solely in Flutter.
Never connect Flutter directly to privileged database credentials. Server validates all permissions, catalog state, order invariants, idempotency and data provenance. Use integer minor units for currency and explicit Asia/Bangkok display timezone; timestamps stored UTC.
Auth: secure server-side sessions or carefully implemented short-lived tokens plus refresh rotation, HTTPS-only cookies when suitable; CSRF mitigation for cookie sessions, password hash where applicable, OTP throttling, session revocation, MFA for admins.
Config via environment variables; provide `.env.example` with no real secrets. Feature gates: DEMO_MODE=true, LIVE_PURCHASE_ENABLED=false, PAYMENT_ENABLED=false, PRIZE_SETTLEMENT_ENABLED=false, OFFICIAL_FEED_ENABLED=false by default. Live-enabled gates must fail closed unless provider credentials + compliance approval are configured.

## 6. DATABASE MODEL
Design relational tables and migrations for:
users, user_profiles, age_verifications, identity_verifications, sessions, consent_records, roles, permissions, role_permissions, user_roles, draw_cycles, ticket_catalog, ticket_inventory, cart_items, orders, order_items, demo_receipts, payment_attempts (placeholder only), provider_reconciliation (placeholder), prize_results, result_import_batches, publication_approvals, announcements, notifications, support_tickets, support_comments, usage_limits, self_exclusions, feature_flags, settings, admin_actions, audit_logs.
Each financial-like or ownership-like event needs idempotency key, explicit state machine, timestamps, source/provenance and audit metadata. Never allow user-side direct updates of order statuses. Implement transaction-safe stock reservation for demo to prevent double reservation. Make audit logs append-only at the app level, with DB permission separation recommended.
Indexes: users by email/phone identity hash, draw date/status, inventory draw+number+state, orders user+created_at, audit actor+timestamp, results draw, and unique idempotency keys.
Seed realistic but entirely fictitious Thai demo records and label them throughout.

## 7. API CONTRACT
REST API versioned at /api/v1. Define OpenAPI and implement representative endpoints:
POST /auth/login, POST /auth/otp/request, POST /auth/otp/verify, POST /auth/logout, GET /me
GET /draws, GET /catalog, GET /catalog/:id, GET/POST/DELETE /cart, POST /demo-checkouts, GET /orders, GET /orders/:id
GET /results, GET /results/:drawId, POST /check-number, GET /notifications, GET/PUT /profile, GET /responsible-use
Admin: GET /admin/dashboard, GET /admin/users, GET /admin/orders, GET /admin/catalog, GET /admin/results, POST /admin/results/import-draft, POST /admin/results/:id/approve, GET /admin/audit, GET /admin/reports, GET/PUT /admin/settings, GET/PUT /admin/feature-flags.
Use standardized pagination, filter DTOs, error format, strict validation, trace IDs, rate limiting, permission guards, and consistent JSON date/number serialization. Mock adapters must match real API contracts exactly.

## 8. PROJECT FILE LAYOUT
lotto_day/
  apps/
    flutter_app/
      lib/
        app/ (bootstrap, router, app_shell)
        core/ (theme, constants, i18n, errors, http, auth, utilities)
        shared/ (widgets, entities, layouts, feedback)
        features/
          auth/ home/ catalog/ cart/ orders/ results/ profile/ notifications/ help/
          admin_dashboard/ admin_users/ admin_catalog/ admin_orders/ admin_results/
          admin_payments/ admin_reports/ admin_access/ admin_audit/ admin_settings/
      assets/ (original branding, fonts, demo placeholders)
      test/ integration_test/ web/
    backend/
      src/modules/ (auth, users, catalog, draws, carts, demo-checkout, orders, results,
                   notifications, admin, audit, reports, settings, compliance)
      prisma/schema.prisma
      prisma/migrations/
      test/
  packages/
    api_contracts/
  infra/
    docker-compose.yml
  docs/
    architecture.md
    design-system.md
    screen-inventory.md
    database-erd.md
    api-spec.yaml
    threat-model.md
    release-checklist.md
  README.md
  .env.example

If monorepo handling complicates Flutter tooling, preserve the separation while keeping `flutter pub get` and standard Flutter CLI commands functional.

## 9. USER WORKFLOWS
A. Guest -> register -> demo verify -> home -> browse -> add sample ticket -> cart -> demo confirmation -> history (no money changes).
B. Guest/member -> enter ticket number -> choose draw -> check publicly sourced result OR labeled demo dataset.
C. Admin -> secure login -> dashboard -> search member/order -> view audit history.
D. Compliance admin -> stage official result import -> validate provenance -> distinct second approver -> publish -> immutable audit.
E. Ops admin -> create/edit sample draw -> activate sample catalog -> expire tickets automatically on configured draw cutoff.
All pathways include appropriate loading, confirmation, form validation and recoverable error states.

## 10. QA & ACCEPTANCE CRITERIA
- Layout screenshots verified at 360x800, 390x844, 430x932, 768x1024, 1280x800, 1440x900; no horizontal overflow.
- Flutter analyze, unit/widget/integration tests, backend lint/unit/e2e tests, database migration/seed and build web must pass.
- Essential demo workflows (register/login, browse, cart, demo checkout, my tickets, results, admin users/orders, staged results approvals, audit) test end-to-end.
- 401/403 backend checks for unauthorized actions, IDOR prevention, input validation, OTP throttling, session revoke, idempotency collision, concurrent reservation, feature flag fail-closed and audit coverage.
- Every user action has feedback; every major view handles empty/error/loading states.
- Production mode MUST not allow real purchase, funds, or result publication until authorized service provider integration is separately completed and verified.

## 11. BUILD ORDER / DELIVERABLES
1. First write docs: architecture decisions, visual design tokens, route/screen inventory, RBAC matrix, ERD, API specification and implementation plan.
2. Generate Flutter app shell/themes/components and responsive route skeletons with attractive polished UI.
3. Build all user screens using typed mock repositories and seed data, then admin screens and charts.
4. Create NestJS/PostgreSQL API and migrations, test data, RBAC, safe demo state machines, audit logging.
5. Replace mock repositories with real API adapters behind feature configuration; keep demo safe and live integrations disabled.
6. Add robust tests, Docker Compose, developer scripts and release docs.
7. Run tests, fix issues, and report what actually passed, what was not executed, and all blocked real-world integrations.

## 12. REQUIRED OUTPUT AND RULES FOR CLAUDE CODE
Write real files, not pseudocode. Start by printing a compact numbered implementation plan, then implement phases sequentially in the repository. Do not ask for cosmetic clarifications: choose the design system above. Prefer complete, working MVP over placeholder screens. Do NOT claim a build/test passed without executing it. Add `make dev`, `make test`, and documented platform commands (or cross-platform npm scripts) to run local dev and all tests. Provide README in Thai describing setup and developer operations, plus a final route list and screenshots where tooling permits.

First user-visible project milestone: a functioning Flutter Web demo with at least five tabs, complete catalog->cart->demo-confirmation flow, result checking with sample data, and a usable `/admin` dashboard on local development. Proceed to deeper backend/QA work without stopping at decorative mockups.


## 13. V2 REFERENCE IMPLEMENTATION (MANDATORY CONTINUATION)
This prompt accompanies a zipped runnable Flutter UI starter: `lotto_day_blue_flutter/`.
**First read and preserve its actual source code** (`lib/main.dart`, `lib/core/theme/app_theme.dart`, `lib/app/app_shell.dart`, `lib/features/user/user_pages.dart`, `lib/features/admin/admin_pages.dart`, `lib/core/data/demo_store.dart`).
Work *from* the blue V2 codebase rather than regenerating the old teal design. The included PNG `design-reference.png` is a visual concept, not a pixel-perfect screen specification.
Existing code: mobile/dt nav, catalog search, in-memory cart, simulated confirmation/receipts, demo result check, admin metrics, and admin module placeholder routes. The initial project does **not** contain secure login, server backend, persistence or real admin CRUD. Treat those as TODO and implement as written in sections 3–12.
Avoid introducing code that resembles or impersonates government-issued applications. Never claim to be the official Paotang, GLO or Krungthai service.

### V2 visual acceptance criteria
1. All customer headers use blue (#0078D7) and optional sky-blue gradient (#00AEEF); background #F4FAFF.
2. Primary submit/confirmation CTA is #FFC700 with navy text; secondary action is primary blue with white text.
3. The top profile area has a blue header, rounded white body cards, clear statuses and no teal remnants.
4. Five-tab mobile navigation is white with blue active state; desktop is a blue/white adaptive layout.
5. Admin uses dark-navy rail, blue selection marker, white metric cards, responsive charts, and action controls.
6. Thai font legibility, dark text on pale surfaces, contrast, 48px tap targets, no overflow at 360–1440 px.
7. No nonfunctional pretend CRUD buttons: implement real demo adapters, API or disabled buttons with honest messaging.
8. Responsive screenshot comparisons for Home, Catalog, Cart, Results, Profile, Admin overview and Admin Users.

### Continue order from starter
A. Verify `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build web`; correct any Flutter SDK/package issues, do not claim tests pass without running them.
B. Implement all remaining customer flows, robust typed state management and Thai i18n; preserve V2 visual tokens.
C. Implement admin features and RBAC backed by NestJS/PostgreSQL, with real persisted demo data and audit logs.
D. Add secure provider-abstraction architecture, mock adapters, feature gates, security and functional tests.
E. Verify web/PWA responsiveness on devices; provide screenshots and a test report.
