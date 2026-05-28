# CoPlan

A co-parenting scheduler. A Flutter app (Android + web) backed by a self-hosted
PocketBase server works out **who is responsible for the children** on any given
day — from a standing weekly schedule, a configurable custody rotation, one-off
requests, and standing recurring arrangements — and shows it on a dashboard,
calendar, and Android home-screen widgets.

Originally built for a single two-parent household, CoPlan now supports
**multiple households**, **multiple children** (including single-child
families), **several rotation schemes**, a **shared mode** for parents who live
together, and **CSV/Excel export** of the schedule.

---

## Features

- **Resolution engine** — pure-Dart, the single source of truth. Priority per
  slot: manual override → weekday rule → custody rotation, with accepted custody
  requests (day transfers + time windows) and recurring arrangements layered on
  by time of day.
- **Households & members** — register, create a household, invite the other
  parent (and optional helpers like a grandparent) via a share code. Each
  household has its own members, children, rotation config, and data.
- **Children** — one or more per household, each with its own colour; events can
  target a specific child or `All`.
- **Rotation schemes** — `weekly` (7/7), `2-2-5-5`, `2-2-3`,
  `alternating weekends`, or a `custom` day-pattern, all anchored to a reference
  date.
- **Shared mode** — for non-separated parents: no rotation; both parents are
  responsible by default (`Both`) and the request flow becomes pickup
  coordination.
- **Custody requests** — one-off day transfers and time-window handovers with
  transport tracking (who collects / who drops off / who returns).
- **Recurring arrangements** — a single editable rule ("every Tuesday Jana
  hands the kids to Bennet at 17:30"). Expanded live for today/future **only on
  weeks the other parent owns the day**, and frozen into immutable history as
  days pass (see below).
- **One-off shared events** — ad-hoc events (birthday parties, school trips)
  visible to both parents regardless of whose week it is, tagged "Both".
- **Calendar views** — week strip and month grid with split-colour cells showing
  mid-day ownership changes.
- **CSV export** — export any date range (past = history, future = planned) to a
  spreadsheet-compatible CSV.
- **Home-screen widgets** — three Android Glance styles (Minimal, Material,
  Timeline), each showing the next 3 events, refreshed every 15 min via
  WorkManager.
- **Local notifications** — new custody-request alerts even when backgrounded.
- **Offline queue** — mutations queued locally when offline, replayed on
  reconnect.

---

## Architecture

```
┌──────────────────────────────┐   HTTPS · PocketBase REST + SSE
│   Flutter app (Android/web)  │ ◄──────────────────────────────► PocketBase LXC
│                              │                                    (Debian/Proxmox)
│  Riverpod providers          │                                       │
│  ResolutionEngine (Dart)     │                                    Cloudflared tunnel
│  WidgetCacheService          │                                       │
│  Glance widgets ◄── SharedPrefs ◄── CoplanSyncWorker (Kotlin)     Public URL
└──────────────────────────────┘        (WorkManager, 15 min)
```

- **Backend** — PocketBase single binary on a Debian LXC, fronted by a
  Cloudflare tunnel. Schema in `backend/pb_migrations/`; server logic
  (the freeze cron) in `backend/pb_hooks/main.pb.js`.
- **State** — Riverpod (`AsyncNotifier`, `FutureProvider`).
- **Engine** (`lib/engine/resolution_engine.dart`) — pure Dart, no Flutter deps
  beyond `TimeOfDay`. Every UI surface builds an engine and asks it; there is no
  parallel resolution logic in the app.
- **Widgets** — Android Glance widgets read pre-resolved events from
  SharedPreferences, written by both the Dart `WidgetCacheService` (on resume /
  mutation) and the Kotlin `CoplanSyncWorker` (every 15 min).

---

## Backend — PocketBase collections

| Collection | Purpose |
|---|---|
| `users` | Accounts. `active_household` points at the user's current household. |
| `households` | Per-household config: `name`, `mode` (`custody`/`shared`), `rotation_anchor`, `rotation_parent_even/odd` (user relations), `rotation_scheme_type`, `rotation_pattern`. |
| `household_members` | Membership: `household`, `user`, `role` (`parent`/`helper`), `display_name`, `status`. |
| `children` | Children per household: `household`, `name`, `color`. |
| `household_invites` | Share codes: `invite_code`, `role`, `expires_at`, `used_by`. |
| `rules_base` | Standing weekly schedule: `child_name`, `day_of_week` (1=Mon…7=Sun), `event_time`, `activity`, `location`, `is_shared`. |
| `manual_overrides` | Date-specific parent substitutions **and** ad-hoc one-off events (`is_adhoc`, `is_shared`). |
| `custody_weekday_rules` | Optional standing full-day weekday ownership override (rare). |
| `custody_requests` | One-off day-transfer / time-window requests; also where recurring occurrences are frozen. |
| `custody_recurring` | Standing recurring arrangements (one editable rule per pattern). |
| `app_settings` | Key/value config (child colours, legacy rotation fallback). |

Most collections carry a `household` relation so data is scoped per household.

---

## Resolution logic

For any date, the responsible parent is resolved in **priority order**:

1. **Manual override** — date-specific record in `manual_overrides`.
2. **Weekday rule** — `custody_weekday_rules` (usually none).
3. **Rotation** — `RotationScheme` pattern from the household's `rotation_anchor`.
   Computed with **UTC epoch math** so DST never shifts parity.

**Accepted custody (real + virtual recurring) layers on top** by time of day:
- **Day transfers** change ownership from their pickup time onward; events before
  the handover stay with the day owner.
- **Time windows** change responsibility only during pickup → return.

`effectiveCustodyFor(date)` merges real accepted requests with virtual recurring
occurrences and is the single list every method reasons over (cached per date).

**Shared mode** short-circuits rotation: `baseOwner`/`weekOwner`/`dayOwner`
return `Both`, and the UI renders a neutral colour.

### Calendar cell rendering
Solid colour = single owner all day; **diagonal split** = ownership changes
mid-day (a day transfer after 00:00, or a window with a definite return time).

---

## Recurring arrangements (logic-future, freeze-past)

A single editable `custody_recurring` record per pattern — no materialised rows.

- **Live expansion** (`ResolutionEngine._virtualRecurringFor`): for today/future
  dates, on/after `start_date`, **only when the day's rotation owner is not the
  recipient** (you can't be handed kids you already have — it self-suppresses on
  the recipient's own weeks), and only when no one-off request already covers the
  date. Virtual occurrences show a "Repeats weekly" line and a **Stop repeating**
  action.
- **Freeze** (`backend/pb_hooks/main.pb.js`, daily 00:05 cron): materialises past
  occurrences into real `custody_requests` rows so history is immutable even if
  the arrangement is later edited or deleted. It iterates per household, mirrors
  the engine's `baseOwner` (rotation pattern + weekday rules), and back-fills the
  last 14 days.

The freeze cron's day-owner logic is a deliberate mirror of the Dart engine —
**keep the two in sync** when changing rotation logic.

---

## Project structure

```
lib/
├── core/                 # pb_client, constants
├── engine/
│   └── resolution_engine.dart   # pure-Dart resolver (the heart of the app)
├── models/               # base_rule, custody_request, recurring_arrangement,
│                         #   manual_override, weekday_rule, household,
│                         #   rotation_scheme, resolved_event, app_colors
├── providers/            # Riverpod providers (schedule, custody, household, …)
├── screens/              # dashboard, calendar, requests, settings, login,
│                         #   register, household_setup, export
├── services/             # queue_service, notification_service, widget_cache_service
└── widgets/              # timeline_card, week_strip, month_grid, sheets, tiles

backend/
├── pb_migrations/        # schema migrations (apply in filename order)
└── pb_hooks/main.pb.js   # freezeRecurring cron

test/                     # unit tests (engine, rotation schemes, models)
```

---

## Build & deploy

```bash
# App (Android)
flutter build apk --release --dart-define=PB_URL=https://your-domain.com

adb install -r build/app/outputs/flutter-apk/app-release.apk

# Web (served by PocketBase)
flutter build web --dart-define=PB_URL=https://your-domain.com
scp -r build/web/* user@server:/opt/coplan/pb_public/

# Backend changes (migration / hook): copy to the server and restart
scp backend/pb_migrations/<file>.js root@<server>:/opt/coplan/pb_migrations/
scp backend/pb_hooks/main.pb.js      root@<server>:/opt/coplan/pb_hooks/main.pb.js
ssh root@<server> 'systemctl restart coplan'
```

| Build flag | Default | Notes |
|---|---|---|
| `PB_URL` | `http://localhost:8090` | PocketBase server URL |

Rotation config now lives **per household** in the `households` collection (set
during household setup), not in a build flag. New migrations should use a
timestamp above the server's latest applied migration.

See `SETUP.md` for full first-time deployment.

---

## Tests

Pure-logic unit tests live in `test/`:

```bash
flutter test
```

- `resolution_engine_test.dart` — rotation, day transfers, windows,
  `parentAtTime`, recurring expansion + conditional, shared mode, override
  precedence, `resolveDay` ordering.
- `rotation_scheme_test.dart` — pattern indexing (incl. negative offsets) and
  presets.
- `models_test.dart` — `fromRecord` parsing and derived getters.

The engine is pure Dart, so it tests without a running PocketBase.
