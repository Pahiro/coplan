# CoPlan

A co-parenting logistics app. A Flutter app (Android + web) backed by a
self-hosted PocketBase server answers three questions for separated parents:
**who has the kids** on any given day, **what's happening** (activities,
exams, handovers), and **who owes whom what** for child-related costs.

The schedule is resolved from a custody rotation, holiday blocks, absences,
standing weekly events, one-off events and exams, and agreed requests (day
handovers, day swaps, time windows) — shown on a dashboard, calendar, and
Android home-screen widgets. Shared expenses are split between parents with a
running net balance, receipts and a settle-up; a shared "to buy" list covers
the things the kids need.

CoPlan supports **multiple households**, **helpers** (e.g. grandparents),
**multiple children**, **several rotation schemes**, a **shared mode** for
parents who live together, and CSV export of schedule and expenses.

---

## Features

### Schedule
- **Resolution engine** — pure Dart, the single source of truth (see below).
- **Rotation schemes** — `weekly` (7/7), `2-2-5-5`, `2-2-3`,
  `alternating weekends`, or a custom day-pattern, anchored to a reference date.
- **Requests** — three kinds, each accepted or declined by the other parent
  (with an optional reason):
  - **Day handover** — someone has the kids from a pickup time for the rest of
    the day and overnight.
  - **Day swap** — trade one of your days for one of your co-parent's. Stored
    as two linked day transfers that are answered and cancelled together.
  - **Time window** — the kids go for a few hours and come back.

  Transport (who collects / drops off / returns) is tracked. The requester can
  edit or withdraw a pending request and cancel an accepted one; the other
  parent is notified. Requests waiting for your answer sit at the top of Today.
- **Events** — standing weekly events (optionally until an end date,
  directional handover times) and one-off events.
- **Exam timetables** — add a child's exam papers in one go. Exams show on
  Today and the calendar (dots in month view) and as a heads-up when planning a
  request on an exam day.
- **Holiday blocks & absences** — date ranges that assign a parent (school
  holidays, trips) or flip custody while a parent is away.
- **Calendar** — week strip and month grid with split-colour cells for mid-day
  ownership changes, swipe navigation, and a "Jana has the kids" chip on Today.
- **Shared mode** — for parents who live together: no rotation; requests become
  pickup coordination.

### Money
- **Shared expenses** — once-off or recurring (monthly/quarterly/annually) child
  costs with categories, per-child tagging, receipt photos, a payee, and a
  percentage split. Amounts in cents, ZAR.
- **Net balance & settle up** — Today shows the net position. The parent who is
  owed on balance confirms the settle-up, which clears every outstanding split
  between the parents in both directions (server route — the parent who owes
  can't clear their own debt).
- **Recurring splits** — a nightly server cron creates each period's split
  (never twice for the same due date) and marks late splits overdue.
- **To buy** — a shared list of things the kids need. "I'll get it" claims an
  item so only one parent buys it; marking it bought offers to add the cost as a
  shared expense.

### Households & infrastructure
- **Households & members** — register, create a household, invite the
  co-parent or a helper via a share code or deep link
  (`https://…/?invite=CODE`). Invite redemption runs server-side; each
  household's data is isolated by access rules.
- **Push notifications** — FCM, sent server-side from PocketBase hooks via a
  loopback sidecar, so they arrive with the app closed. Realtime (SSE)
  subscriptions keep open screens up to date, and the app catches up on resume.
- **Home-screen widgets** — three Android Glance styles showing the next 3
  events in the parents' colours, refreshed on app resume and by WorkManager.
- **Offline** — schedule data is cached; requests, events, to-buy items and
  expenses queue locally and replay on reconnect. Records carry client-generated
  ids so a replay can never create a duplicate.
- **In-app updater** — compares the build number against `app_settings` and
  offers a download/install banner with release notes.
- **Exports** — schedule (any date range) and expenses (with splits) as CSV.

---

## Architecture

```
┌──────────────────────────────┐   HTTPS · PocketBase REST + SSE
│   Flutter app (Android/web)  │ ◄──────────────────────────────► PocketBase LXC
│                              │                                    (Debian/Proxmox)
│  Riverpod providers          │       pb_hooks:                       │
│  ResolutionEngine (Dart)     │       · settle-up / accept-invite  Cloudflared tunnel
│  WidgetCacheService          │       · recurring splits cron         │
│  Glance widgets ◄── SharedPrefs ◄── CoplanSyncWorker (Kotlin)     Public URL
└──────────────────────────────┘        (WorkManager, 15 min)
                                        FCM ◄── coplan-push sidecar (loopback)
```

- **Backend** — PocketBase v0.22 on a Debian LXC behind a Cloudflare tunnel.
  Schema in `backend/pb_migrations/`; server logic in
  `backend/pb_hooks/main.pb.js` (helpers in `coplan_utils.js` — v0.22 runs each
  handler in an isolated context, so handlers `require()` them).
- **State** — Riverpod. Source collections are `FutureProvider`/`AsyncNotifier`s
  cached offline; derived views (dashboard, calendar weeks, day owners) watch
  them. `refreshAppData()` re-fetches everything (pull-to-refresh, resume,
  reconnect).
- **Engine** (`lib/engine/resolution_engine.dart`) — pure Dart. Every surface
  builds an engine via `engine_factory.dart` (or `scheduleEngineProvider`).
- **⚠️ Two copies** — the engine's logic is mirrored in the Kotlin
  `CoplanSyncWorker` for the widgets. **Change one → update the other.**
- **UI** — Material 3 with a shared-axis motion system (`animations` package),
  staggered list entrances and skeleton loaders; motion respects reduce-motion.

---

## Backend — PocketBase collections

| Collection | Purpose |
|---|---|
| `users` | Accounts. `active_household` points at the user's current household. Listable only by yourself. |
| `households` | `name`, `mode` (`custody`/`shared`), `owner`, `rotation_anchor`, `rotation_parent_even/odd`, `rotation_scheme_type`, `rotation_pattern`. |
| `household_members` | `household`, `user`, `role` (`parent`/`helper`), `display_name`, `preferred_color`. |
| `children` | Children per household: `name`, `color`. |
| `household_invites` | Share codes: `invite_code`, `role`, `expires_at`, `used_by`. Redeemed server-side. |
| `rules_base` | Standing weekly events: `child_name`, `day_of_week`, `event_time`, `activity`, `location`, `is_shared`, `handover_from`, `end_date`. |
| `manual_overrides` | One-off events (`is_adhoc`, `kind` = `''`/`exam`, `note`, `end_time`) and date-specific parent overrides. |
| `custody_requests` | Day handovers, time windows and swap legs (`swap_group`). Created pending; only the recipient changes status. |
| `holiday_blocks` | Date ranges assigning one parent. |
| `absence_periods` | Self-declared absences — custody flips to the other parent. |
| `shared_expenses` | Child costs: amount (cents), category, recurrence, `paid_by`, receipt. Edited by their creator. |
| `expense_splits` | Per-parent obligations: `amount_due`, `status` (pending/overdue/paid). Changed only by the expense's payer (or the settle-up route). |
| `needs` | The to-buy list: `title`, `child_name`, `note`, `needed_by`, `status` (open/claimed/bought), `claimed_by`, `bought_by`, `expense`. |
| `device_tokens` | FCM tokens per user. |
| `app_settings` | In-app updater keys (`latest_build`, `latest_version`, `apk_url`, `update_notes`). Read-only for users. |

`custody_weekday_rules` and `custody_recurring` are retired (locked to admin).

Every household-owned collection carries a `household` relation, and access
rules restrict reads/writes to members of that household. **Every create must
stamp `household`.** Hardened rules: migration `1779400027`.

---

## Resolution logic

Who has the kids on a date, in priority order:

1. **Accepted day transfer** (handover or swap leg) — from its pickup time.
2. **Absence** — the absent parent's scheduled day flips to the other parent.
3. **Holiday block** covering the date.
4. **Rotation** — `RotationScheme` pattern from the anchor, using **UTC epoch
   math** so DST never shifts parity.

Per event:
- A standing event's date-specific **manual override** beats 2–4.
- **Accepted time windows** change responsibility during pickup → return;
  **day transfers** from their pickup time. Per-child requests don't move
  siblings.
- **One-off events** (and exams) resolve their parent live, so later swaps,
  absences and holidays are always reflected.

**Shared mode** short-circuits rotation: owners are `Both`.

### Calendar cell rendering
Solid colour = one owner all day; **diagonal split** = ownership changes mid-day
(a transfer after 00:00, or a window with a return time). The split lives once,
in `lib/widgets/day_split.dart`.

---

## Project structure

```
lib/
├── core/        # pb_client, constants, expense_categories
├── engine/      # resolution_engine.dart (pure Dart), engine_factory.dart
├── models/      # custody_request (+ RequestGroup), manual_override, need,
│                #   household, rotation_scheme, resolved_event, holiday_block,
│                #   absence_period, shared_expense, expense_split, app_colors
├── providers/   # schedule, custody, needs, expense, household, absence,
│                #   holiday, realtime, refresh, navigation, …
├── screens/     # dashboard, calendar, requests, expenses (+ needs view,
│   └── settings/#   detail, form, export), login, register, household_setup
├── services/    # queue_service (offline), push_service, notification_service,
│                #   update_service, widget_cache_service, offline_cache
├── utils/       # dates, ids, csv_export
└── widgets/     # timeline_card, week_strip, month_grid, day_split, sheets
                 #   (new request, event, exam timetable, need, absence), …

backend/
├── pb_migrations/            # schema migrations (apply in filename order)
├── pb_hooks/main.pb.js       # routes, cron, push hooks
├── pb_hooks/coplan_utils.js  # helpers require()d by the handlers
└── push-sidecar/             # loopback FCM sender

android/…/CoplanSyncWorker.kt  # widget refresh (mirrors the engine)
test/                          # engine, rotation scheme and model tests
```

---

## Build, release & deploy

**One-shot release** (version bump, backend, APK, app_settings, web):

```bash
./deploy.sh              # bumps patch+build, deploys everything
./deploy.sh --no-bump    # deploy the pubspec version as-is
# flags: --skip-build --skip-apk --skip-backend --skip-web
```

The deploy publishes the repo-root **`RELEASE_NOTES`** as the update banner
text — update it alongside feature work (no double quotes).

**CI**: every push to `main` runs the tests, builds the APK and publishes a
GitHub release tagged from the pubspec version, with `RELEASE_NOTES` as the body.

### CI secrets
The signing key and `google-services.json` aren't in the repo. Add them once as
repository secrets. The keystore **must be the one existing installs were signed
with** (the debug keystore of the machine that runs `deploy.sh`), or phones
can't update in place:

```bash
base64 -w0 ~/.android/debug.keystore        | gh secret set ANDROID_KEYSTORE_BASE64 --repo Pahiro/coplan
gh secret set ANDROID_KEYSTORE_PASSWORD --repo Pahiro/coplan --body android
gh secret set ANDROID_KEY_ALIAS         --repo Pahiro/coplan --body androiddebugkey
gh secret set ANDROID_KEY_PASSWORD      --repo Pahiro/coplan --body android
base64 -w0 android/app/google-services.json | gh secret set GOOGLE_SERVICES_JSON --repo Pahiro/coplan
```

Keep a backup of that keystore somewhere safe — losing it means no further
in-place updates.

**Manual builds**:

```bash
flutter build apk --release --dart-define=PB_URL=https://your-domain.com
flutter build web --dart-define=PB_URL=https://your-domain.com
```

⚠️ Committing a migration does **not** deploy it — it must reach the server's
`pb_migrations/` and the service restarted (deploy.sh does this after backing up
`pb_data`). Number new migrations above the server's latest applied one.

See `SETUP.md` for first-time deployment and `CLAUDE.md` for operational
conventions.

---

## Tests

```bash
flutter test
```

- `resolution_engine_test.dart` — rotation, holidays, day transfers and windows,
  per-child custody, day swaps, one-off events resolved live, exams, absences,
  shared mode, override precedence, handover rules, end dates, ordering.
- `rotation_scheme_test.dart` — pattern indexing (incl. negative offsets).
- `models_test.dart` — record parsing, swap grouping, needs, colours.

The engine is pure Dart, so it tests without a running PocketBase.
