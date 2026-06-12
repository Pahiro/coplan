# CoPlan

A co-parenting logistics app. A Flutter app (Android + web) backed by a
self-hosted PocketBase server answers two questions for separated parents:
**who is responsible for the children** on any given day, and **who owes whom
what** for child-related costs.

The schedule is resolved from a standing weekly schedule, a configurable
custody rotation, holiday blocks, absences, one-off requests, and standing
recurring arrangements — and shown on a dashboard, calendar, and Android
home-screen widgets. Shared expenses are split between parents with a running
net balance, receipts, and a one-tap settle-up.

Originally built for a single two-parent household, CoPlan supports
**multiple households**, **helpers** (e.g. grandparents), **multiple
children**, **several rotation schemes**, a **shared mode** for parents who
live together, and CSV export of both schedule and expenses.

---

## Features

### Schedule
- **Resolution engine** — pure-Dart, the single source of truth. Priority per
  slot: manual override → weekday rule → holiday block → custody rotation,
  with absences flipping the scheduled parent and accepted custody requests
  (day transfers + time windows) layered on by time of day.
- **Rotation schemes** — `weekly` (7/7), `2-2-5-5`, `2-2-3`,
  `alternating weekends`, or a custom day-pattern, anchored to a reference date.
- **Shared mode** — for non-separated parents: no rotation; both parents are
  responsible (`Both`) and the request flow becomes pickup coordination.
- **Custody requests** — one-off day transfers and time-window handovers with
  transport tracking (who collects / drops off / returns), accept/decline with
  an optional reason, and an upcoming/past history view.
- **Recurring arrangements** — a single editable rule ("every Tuesday Jana
  hands the kids to Bennet at 17:30"), expanded live for future weeks and
  frozen into immutable history as days pass (see below).
- **Holiday blocks & absences** — date ranges that override the rotation
  (school holidays, trips) or flip custody while a parent is away.
- **One-off shared events** — ad-hoc events (birthday parties, school trips)
  visible to both parents regardless of whose week it is.
- **Calendar** — week strip and month grid with split-colour cells for mid-day
  ownership changes, swipe navigation, and a colour-coded day-owner chip on
  the dashboard ("Jana has the kids").

### Money
- **Shared expenses** — once-off or recurring (monthly/quarterly/annually)
  child costs with categories, per-child tagging, receipt photos, and a
  percentage split to the other parent. Amounts stored in cents, ZAR.
- **Net balance & settle up** — the dashboard shows the net position; Settle
  Up clears every outstanding split in both directions so one EFT settles
  the slate.
- **Payment details** — each parent can store banking info / a payment link,
  shown to the owing parent on the expense.
- **Recurring split generation** — a nightly server cron materialises the next
  split when a recurring expense falls due; overdue splits are auto-flagged.

### Households & infrastructure
- **Households & members** — register, create a household, invite the
  co-parent or a helper via a share code or deep link
  (`https://…/?invite=CODE` opens straight into join/registration). Invite
  redemption runs server-side; each household's data is isolated by
  access rules.
- **Realtime notifications** — PocketBase SSE pushes custody-request and
  expense activity to the other parent's device while the app runs; the
  Android sync worker also notifies about new pending requests in the
  background.
- **Home-screen widgets** — three Android Glance styles, each showing the next
  3 resolved events, refreshed every 15 min via WorkManager and on app resume.
- **Offline queue** — custody requests, shared events, and expense creation
  queue locally when offline and replay on reconnect.
- **In-app updater** — the app compares its build number against
  `app_settings` and offers a download/install banner with release notes.
- **Exports** — schedule (any date range; past = history, future = plan) and
  expenses (incl. splits, for tax records) as CSV.

---

## Architecture

```
┌──────────────────────────────┐   HTTPS · PocketBase REST + SSE
│   Flutter app (Android/web)  │ ◄──────────────────────────────► PocketBase LXC
│                              │                                    (Debian/Proxmox)
│  Riverpod providers          │                                       │
│  ResolutionEngine (Dart)     │       pb_hooks crons:              Cloudflared tunnel
│  WidgetCacheService          │       · freezeRecurring 00:05         │
│  Glance widgets ◄── SharedPrefs ◄── CoplanSyncWorker (Kotlin)     Public URL
└──────────────────────────────┘        (WorkManager, 15 min)
```

- **Backend** — PocketBase single binary on a Debian LXC, fronted by a
  Cloudflare tunnel. Schema in `backend/pb_migrations/`; server logic in
  `backend/pb_hooks/main.pb.js`: the `freezeRecurring` cron (00:05), the
  `generateRecurringSplits` cron (00:15), and the privileged
  `POST /api/coplan/accept-invite` route (a joiner can't read the invite or
  self-create membership under the household-scoped rules).
- **State** — Riverpod (`AsyncNotifier`, `FutureProvider`).
- **Engine** (`lib/engine/resolution_engine.dart`) — pure Dart, no Flutter
  deps beyond `TimeOfDay`. Every UI surface builds an engine via
  `engine_factory.dart` and asks it; there is no parallel resolution logic in
  the Flutter app.
- **⚠️ Three sync points** — the engine's day-owner logic is deliberately
  mirrored in two other places: the Kotlin `CoplanSyncWorker` (widgets) and
  the `freezeRecurring` cron (history). **Change one → update all three.**
- **Widgets** — Android Glance widgets read pre-resolved events from
  SharedPreferences, written by both the Dart `WidgetCacheService` (on
  resume / mutation) and the Kotlin worker (every 15 min).
- **UI** — Material 3 with a shared-axis motion system (`animations` package):
  page transitions, container transforms (expense tile → detail), staggered
  list entrances, and skeleton loaders. All motion respects the system
  reduce-motion setting.

---

## Backend — PocketBase collections

| Collection | Purpose |
|---|---|
| `users` | Accounts. `active_household` points at the user's current household. |
| `households` | Per-household config: `name`, `mode` (`custody`/`shared`), `owner`, `rotation_anchor`, `rotation_parent_even/odd` (user relations), `rotation_scheme_type`, `rotation_pattern`. |
| `household_members` | Membership: `household`, `user`, `role` (`parent`/`helper`), `display_name`, `preferred_color`. |
| `children` | Children per household: `household`, `name`, `color`. |
| `household_invites` | Share codes: `invite_code`, `role`, `expires_at`, `used_by`. Redeemed server-side. |
| `rules_base` | Standing weekly schedule: `child_name`, `day_of_week` (1=Mon…7=Sun), `event_time`, `activity`, `location`, `is_shared`, optional directional `handover_from`. |
| `manual_overrides` | Date-specific parent substitutions **and** ad-hoc one-off events (`is_adhoc`, `is_shared`, `note`, `end_time`). |
| `custody_weekday_rules` | Standing full-day weekday ownership override. |
| `custody_requests` | One-off day-transfer / time-window requests; also where recurring occurrences are frozen. |
| `custody_recurring` | Standing recurring arrangements (one editable rule per pattern). |
| `holiday_blocks` | Date ranges assigning one parent (school holidays, trips). |
| `absence_periods` | Self-declared absences — custody flips to the other parent for the range. |
| `shared_expenses` | Child costs: amount (cents), category, recurrence, `paid_by`, `receipt` file. |
| `expense_splits` | Per-parent payment obligations: `amount_due`, `status` (pending/overdue/paid), payment reference. |
| `payment_details` | Per-user banking info / payment link shown to the owing parent. |
| `app_settings` | Key/value config — in-app updater keys (`latest_build`, `latest_version`, `apk_url`, `update_notes`) and legacy fallbacks. |

Every household-owned collection carries a `household` relation, and access
rules (migration `1779400008`+) restrict reads/writes to members of that
household. **Every create must stamp `household`** or the server denies it.

---

## Resolution logic

For any date, the responsible parent is resolved in **priority order**:

1. **Manual override** — date-specific record in `manual_overrides` (wins
   even over absences: it's an explicit decision).
2. **Weekday rule** — `custody_weekday_rules` (usually none).
3. **Holiday block** — a `holiday_blocks` range covering the date.
4. **Rotation** — `RotationScheme` pattern from the household's
   `rotation_anchor`. Computed with **UTC epoch math** so DST never shifts
   parity.

An **absence** covering the date flips the scheduled parent to the other
rotation parent (steps 2–4 only).

**Accepted custody (real + virtual recurring) layers on top** by time of day:
- **Day transfers** change ownership from their pickup time onward; events
  before the handover stay with the day owner.
- **Time windows** change responsibility only during pickup → return.

`effectiveCustodyFor(date)` merges real accepted requests with virtual
recurring occurrences and is the single list every method reasons over
(cached per date). Per-child custody is supported: a transfer for one child
doesn't move siblings.

**Shared mode** short-circuits rotation: `baseOwner`/`weekOwner`/`dayOwner`
return `Both`, and the UI renders a neutral colour.

### Calendar cell rendering
Solid colour = single owner all day; **diagonal split** = ownership changes
mid-day (a day transfer after 00:00, or a window with a definite return
time). The split computation lives once, in `lib/widgets/day_split.dart`,
shared by the week strip and month grid.

---

## Recurring arrangements (logic-future, freeze-past)

A single editable `custody_recurring` record per pattern — no materialised rows.

- **Live expansion** (`ResolutionEngine._virtualRecurringFor`): for
  today/future dates, on/after `start_date`, **only when the day's rotation
  owner is not the recipient** (it self-suppresses on the recipient's own
  weeks), skipping days the recipient is absent, and only when no one-off
  request already covers the date. Virtual occurrences show a "Repeats
  weekly" line and a **Stop repeating** action.
- **Freeze** (`backend/pb_hooks/main.pb.js`, daily 00:05 cron): materialises
  past occurrences into real `custody_requests` rows so history is immutable
  even if the arrangement is later edited or deleted. It iterates per
  household, mirrors the engine's `baseOwner`, and back-fills the last 14 days.

---

## Project structure

```
lib/
├── core/                 # pb_client, constants, expense_categories
├── engine/
│   ├── resolution_engine.dart   # pure-Dart resolver (the heart of the app)
│   └── engine_factory.dart      # builds an engine from a household config
├── models/               # base_rule, custody_request, recurring_arrangement,
│                         #   manual_override, weekday_rule, household,
│                         #   rotation_scheme, resolved_event, holiday_block,
│                         #   absence_period, shared_expense, expense_split,
│                         #   payment_details, app_colors
├── providers/            # Riverpod providers (schedule, custody, expense,
│                         #   household, absence, holiday, realtime, …)
├── screens/              # dashboard, calendar, requests, expenses (+detail,
│   └── settings/         #   form, export), login, register, household_setup;
│                         #   settings sub-screens (household, schedule,
│                         #   appearance, time-away, payment, account)
├── services/             # queue_service (offline), notification_service,
│                         #   update_service, widget_cache_service
├── utils/                # dates, csv_export
└── widgets/              # timeline_card, week_strip, month_grid, day_split,
                          #   form_fields, common (dialogs/sheets/errors),
                          #   motion, skeleton, sheets, tiles

backend/
├── pb_migrations/        # schema migrations (apply in filename order)
└── pb_hooks/main.pb.js   # crons (freezeRecurring, generateRecurringSplits)
                          #   + accept-invite route

android/…/CoplanSyncWorker.kt  # widget refresh + background notifications
test/                          # unit tests (engine, rotation schemes, models)
```

---

## Build, release & deploy

**One-shot release** (version bump, backend, APK, app_settings, web):

```bash
./deploy.sh              # bumps patch+build, deploys everything
./deploy.sh --no-bump    # deploy the pubspec version as-is
# flags: --skip-build --skip-apk --skip-backend --skip-web
```

The deploy sets the in-app updater keys in `app_settings` and publishes the
contents of the repo-root **`RELEASE_NOTES`** file as the update banner text —
update that file alongside feature work.

**CI**: every push to `main` builds the APK and publishes/updates a GitHub
release tagged from the pubspec version (`v3.1.0` → `coplan-v3.1.0.apk`),
with `RELEASE_NOTES` as the body.

**Manual builds**:

```bash
flutter build apk --release --dart-define=PB_URL=https://your-domain.com
flutter build web --dart-define=PB_URL=https://your-domain.com
```

| Build flag | Default | Notes |
|---|---|---|
| `PB_URL` | `http://localhost:8090` | PocketBase server URL (users can override at login) |

⚠️ Committing a migration does **not** deploy it — it must reach the server's
`pb_migrations/` and the service restarted (deploy.sh does this; it backs up
`pb_data` first). Number new migrations above the server's latest applied one.

See `SETUP.md` for full first-time deployment and `CLAUDE.md` for operational
conventions.

---

## Tests

Pure-logic unit tests live in `test/`:

```bash
flutter test
```

- `resolution_engine_test.dart` — rotation, day transfers, windows,
  `parentAtTime`, recurring expansion + conditional, absences, shared mode,
  override precedence, `resolveDay` ordering.
- `rotation_scheme_test.dart` — pattern indexing (incl. negative offsets) and
  presets.
- `models_test.dart` — `fromRecord` parsing and derived getters.

The engine is pure Dart, so it tests without a running PocketBase.
