# CoPlan — Design & Logic

A working reference for the architecture, the resolution logic, and the planned
roadmap. Read alongside `README.md` (feature/stack overview) and `SETUP.md`
(deployment). This document is the place to capture *why* things work the way
they do and where they're heading.

---

## 1. What CoPlan is

A co-parenting scheduler for two parents. A Flutter app (Android + web) talks to
a self-hosted PocketBase backend. The core job: given a date, work out **who is
responsible for the children**, what events happen, and who handles transport —
then show that on a dashboard, calendar, and home-screen widgets.

Currently hardwired for a single two-parent household (see §8). The roadmap in
§9 is about generalising it.

---

## 2. Architecture

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

- **Backend**: PocketBase 0.22.22 single binary on a Debian LXC, fronted by a
  Cloudflare tunnel. Migrations in `backend/pb_migrations/`, server logic in
  `backend/pb_hooks/main.pb.js`.
- **App state**: Riverpod (`AsyncNotifier`, `FutureProvider`).
- **The engine** (`lib/engine/resolution_engine.dart`) is pure Dart and is the
  **single source of truth** for resolving a day. Every UI surface builds an
  engine and asks it — there is no parallel resolution logic in the app.
- **Widgets**: Android Glance widgets read pre-resolved events from
  SharedPreferences. Two writers feed that cache (see §6) — this is the main
  source of "the app is right but the widget is stale" issues.

### Server topology (as deployed)
- Host: Debian LXC at `192.168.1.119`, public via `https://coplan.vdgryp.co.za`.
- PocketBase runs from `/opt/coplan/` as the `coplan` systemd service.
  `pb_data/` holds `data.db` (SQLite). Migrations auto-apply on `serve` start.
- **Note**: the server's migration set has drifted from the repo — it contains
  admin-UI-generated migrations (`1779204261_*`, `1779208234_*`) that aren't in
  git, and historically was missing `1746000009_drop_legacy_tables.js`. When
  adding a migration, name it with a timestamp **above the server's latest**
  (we used `1779300000_…`) so ordering stays clean.

---

## 3. Data model (PocketBase collections)

| Collection | Purpose |
|---|---|
| `users` | Parent accounts. `name` must be exactly `"Bennet"` or `"Jana"` (see §8). `preferred_color`. |
| `rules_base` | Standing weekly schedule: `child_name`, `day_of_week` (1=Mon…7=Sun), `event_time`, `activity`, `location`, `is_shared`. |
| `manual_overrides` | Date-specific records: parent substitutions *and* ad-hoc one-off events (`is_adhoc`, `is_shared`, `activity`, `location`). |
| `custody_weekday_rules` | **Legacy / dormant.** Full-day weekday ownership override. Caused bugs when (mis)used for repeats; superseded by `custody_recurring`. Kept only so old data/engine refs don't break. Prefer not to use. |
| `custody_requests` | One-off day-transfer / time-window requests between parents. Drives notifications. Also where recurring occurrences get **frozen** (§5). |
| `custody_recurring` | Standing recurring arrangements (the logic-based repeat — §5). |
| `app_settings` | Key/value config: child colours, and the **rotation anchor + parity parents** used by the server freeze cron. |

### `custody_requests` key fields
`date`, `from_parent`, `to_parent`, `child_name`, `pickup_time`, `return_time`
(empty = day transfer), `return_time_tbd`, `status`
(`pending|accepted|declined|completed`), `note`, `created_by`,
`requested_from`, `to_parent_collects`, `to_parent_returns`.

- **Day transfer** = no return time → `to_parent` keeps the kids from pickup
  onward.
- **Window** = has a return time → kids return to `from_parent` at `return_time`.

### `custody_recurring` key fields
`day_of_week`, `to_parent` (recipient; the *from* parent is implicit = whoever
owns the day that week), `child_name`, `pickup_time`, `return_time`(+`_tbd`),
`to_parent_collects`, `to_parent_returns`, `start_date`, `note`, `active`,
`created_by`.

### `app_settings` rotation keys (consumed by the freeze cron)
`rotation_anchor` = `2026-05-18`, `rotation_parent_even` = `Bennet`,
`rotation_parent_odd` = `Jana`. **Keep these in sync with the client's
`--dart-define=ROTATION_ANCHOR`.**

---

## 4. Resolution engine logic

For any date, responsibility is resolved in **priority order**:

1. **Manual override** — date-specific record in `manual_overrides`
   (non-adhoc parent substitution).
2. **Weekday rule** — `custody_weekday_rules` (legacy; usually none).
3. **Week rotation** — even/odd weeks from the Monday `ROTATION_ANCHOR`.
   Parity even = `Bennet`, odd = `Jana`. (`weekOwner` / `baseOwner`.)

**Accepted custody (real + virtual recurring) layers on top** via `parentAtTime`:
- **Day transfers** change day ownership from their pickup time onward. Events
  *before* the pickup stay with the day owner.
- **Time windows** change responsibility only during pickup → return.

Key methods:
- `dayOwner(date)` — primary owner for the whole day (transfer > weekday rule > rotation).
- `baseOwner(date)` — owner ignoring transfers (weekday rule ?? rotation). Used for split rendering and the recurring conditional.
- `parentAtTime(date, time)` — responsible parent at a specific time (applies windows then transfers).
- `effectiveCustodyFor(date)` — **the merge point**: real accepted requests for the date **plus** virtual recurring occurrences (§5). All the methods above and `resolveDay` reason over this, so every surface sees recurring transfers consistently.
- `dayTransferFor(date)` — the effective day transfer (real or virtual), used by the calendar split painters.

### Calendar cell rendering (`week_strip.dart`, `month_grid.dart`)
- Solid colour = single owner all day.
- **Diagonal split** = ownership changes mid-day. Drawn when there's a partial
  day transfer (pickup after 00:00) **or** a window with a definite return time.
  A window that covers all events *and has no return time* renders solid; with a
  return time it always splits (kids come back).
- Split colours come from the transfer's `from_parent`/`to_parent` **directly**
  (not `baseOwner`) — this avoids a weekday rule painting both halves the same
  colour.

---

## 5. Recurring arrangements (logic-based, freeze-past)

The headline subsystem. Replaces two earlier failed approaches (full-day
weekday rules, and materialising 26 frozen rows).

**Model**: one editable `custody_recurring` record per pattern. No fixed date.

**Live expansion (today + future)**: `ResolutionEngine._virtualRecurringFor`
expands an arrangement into a *virtual* `CustodyRequest` for a date only when:
- the weekday matches and the date is on/after `start_date`;
- the date is **today or later** (past is served by frozen rows);
- **the day's rotation owner is NOT the recipient** — the conditional that
  makes it sane: you can't be handed kids you already have, so it self-
  suppresses on the recipient's own weeks;
- no real request already covers that date+child (one-off requests win).

Virtual occurrences carry a synthetic id `recurring:<arrangementId>:<date>` and
surface in `ResolvedEvent.recurringId`. The timeline card shows a "Repeats
weekly" line and a **Stop repeating** action (deletes the arrangement; past
frozen rows are untouched).

**Freeze (past) — `backend/pb_hooks/main.pb.js`**: a daily cron
(`freezeRecurring`, 00:05) materialises occurrences with `date < today` into
real `custody_requests` rows (status `accepted`), so history is immutable even
if the arrangement is later edited or deleted. It back-fills the last 14 days
(covers brief downtime), uses the `app_settings` rotation keys to compute the
day owner, and skips dates already covered by a real request. `created_by` /
`requested_from` are set to the two distinct parents so **both** can see the
frozen row (PocketBase list rule requires membership).

**Net effect for "every Tuesday Jana hands the kids to Bennet at 17:30"**
(anchor 2026-05-18 = Bennet/even):
- Jana's Tuesdays (26 May, 9 Jun, 23 Jun…): virtual split, banner at 17:30.
- Bennet's Tuesdays (2 Jun, 16 Jun…): **nothing** — he already has them.
- School pickup at 16:00 stays Jana's; only 17:30 onward flips to Bennet.

**UI entry point**: the "Repeat every …" toggle on a custody request's edit
sheet (`custody_request_edit_sheet.dart`) creates/deletes the arrangement via
`RecurringArrangementsNotifier` (`schedule_provider.dart`).

### Requests page (`requests_screen.dart`)
Forward-looking action list: hides past-dated requests (history lives on the
calendar) and sorts upcoming soonest-first. Recurring arrangements never appear
here — future occurrences are virtual (not stored) and frozen ones always carry
a past date.

---

## 6. Android widgets & the two-writer problem

Three Glance widget styles (Minimal, Material, Timeline) read the next 3 events
from SharedPreferences key `coplan_widget_events`. **Two independent writers**:

1. **Dart** `WidgetCacheService` — runs on app resume / after mutations. Now
   passes recurring arrangements to the engine, so app-written cache is correct.
2. **Kotlin** `CoplanSyncWorker` (WorkManager, 15 min) — **reimplements the
   engine in Kotlin**. It currently knows about base rules, weekday rules,
   manual overrides, and custody requests, but **NOT yet `custody_recurring`**.

⚠️ **Known gap / TODO**: port the recurring-arrangement expansion (and the
conditional) into `CoplanSyncWorker.kt`. Until then, home-screen widgets won't
reflect recurring occurrences except right after the app itself refreshes the
cache. Every change to the Dart engine's resolution logic must be mirrored here.

---

## 7. Conventions

- **Parent names are identifiers**, not labels: `"Bennet"` / `"Jana"` are
  matched literally across Dart (`AppConstants.parentBennet/parentJana`),
  PocketBase records, and the JS hook. Renaming a user breaks resolution.
- **Rotation anchor** is a build-time `--dart-define=ROTATION_ANCHOR=YYYY-MM-DD`
  (a Monday of a known Bennet week) AND a server `app_settings` value. Both must
  agree.
- **Dates** are stored as `"YYYY-MM-DD"` strings; times as `"HH:MM"`.
- Migrations: timestamp above the server's latest applied migration.

---

## 8. Current limitations / tech debt

- **Single household, hardcoded**: exactly two parents (`Bennet`/`Jana`) and two
  children (`Henri`/`Chris`) are baked into `constants.dart`, `AppColors`, child
  dropdowns, and the rotation seeds. No multi-tenancy.
- **One rotation scheme**: weekly even/odd only.
- **Widget Kotlin engine lags** the Dart engine (§6).
- **Rotation anchor duplicated** (build flag + app_settings) and must be kept in
  sync manually.
- `custody_weekday_rules` is dead weight kept for back-compat.
- Server migration drift vs. repo (§2).

---

## 9. Planned features (roadmap)

These are intentionally captured for future work. Each notes the main pieces of
the current design that would need to change.

### 9.1 Multi-user / multi-household registration
Let any user register, create a household, and add their own children (one or
more — single-child families must work).

Design notes:
- Introduce a `households` (or `families`) collection; `users`, `children`,
  `rules_base`, overrides, requests, recurring all gain a `household` relation.
- Replace hardcoded `parentBennet`/`parentJana` with **per-household parent
  roles** resolved from `users`. The engine should take the two (or N) parent
  identities as data, not constants. `AppColors` and child dropdowns become
  data-driven from a `children` collection.
- PocketBase list/view rules scope every collection to the caller's household.
- Rotation anchor + parity parents move from global `app_settings` to
  per-household config (and so does the freeze cron's lookup).
- Touch points: `constants.dart`, `app_colors.dart`, `resolution_engine.dart`
  (parameterise parents), all providers' fetches (filter by household), the
  freeze hook, and the child `DropdownMenuItem`s in the sheets.

### 9.2 Co-parenting rotation variations (2-2-5-5, 2-2-3, alternating, custom)
Today rotation is a single weekly even/odd parity. Generalise to a **rotation
scheme** abstraction.

Design notes:
- Define a `rotation_scheme` per household: e.g. `weekly`, `2-2-3` (2-2-5-5
  fortnight), `alternating_weekends`, or a `custom` day-pattern with an anchor.
- The engine's `weekOwner`/`baseOwner` becomes `dayOwner(date)` driven by the
  scheme: map "days since anchor" → owner via the pattern. Keep it pure so the
  Kotlin worker and JS freeze cron can mirror it.
- The freeze cron's `weekOwner` JS helper must implement the same scheme — keep
  the scheme math trivially portable (a small pattern array + anchor).
- UI: a scheme picker in settings; the calendar split logic is unaffected
  (it already asks the engine).

### 9.3 Non-separated parents (shared household pickup coordination)
A mode for parents who live together and just want to coordinate pickups/drop-
offs rather than custody rotation.

Design notes:
- A household `mode` flag: `custody` (rotation, current behaviour) vs `shared`
  (no rotation; both parents are always "responsible" by default).
- In `shared` mode the engine skips rotation entirely; events default to "both"
  and the request flow becomes "can you do this pickup?" (a request to take a
  specific event/time, not to transfer custody of the day).
- Reuse `custody_requests` but reframe UI labels in `shared` mode (pickup
  request vs custody transfer). The `is_shared`/"Both" badge already exists.

### 9.4 Export history to Excel
Export the resolved history (and/or raw requests) to a spreadsheet.

Design notes:
- History is partly computed (engine) and partly stored (frozen rows,
  overrides). Decide the export source: simplest is to resolve a date range via
  the engine and flatten each day's `ResolvedEvent`s to rows (date, child,
  activity, responsible parent, transport, source).
- Implementation options: client-side `.xlsx` generation (e.g. the `excel`
  Dart package) with a date-range picker on a new export screen; or a server
  endpoint/hook that streams a generated file.
- Columns to consider: date, weekday, child, event/activity, location,
  responsible parent, transport (who collects/returns), type
  (base/override/custody/recurring), shared?.

---

## 10. Build & deploy quick reference

```bash
# App (Android)
flutter build apk --release \
  --dart-define=PB_URL=https://coplan.vdgryp.co.za \
  --dart-define=ROTATION_ANCHOR=2026-05-18

adb install -r build/app/outputs/flutter-apk/app-release.apk

# Backend changes (migration / hook): copy to the LXC and restart
scp backend/pb_migrations/<file>.js root@192.168.1.119:/opt/coplan/pb_migrations/
scp backend/pb_hooks/main.pb.js     root@192.168.1.119:/opt/coplan/pb_hooks/main.pb.js
ssh root@192.168.1.119 'systemctl restart coplan'
```

| Build flag | Default | Notes |
|---|---|---|
| `PB_URL` | `http://localhost:8090` | PocketBase URL |
| `ROTATION_ANCHOR` | `2026-05-18` | Monday of a known Bennet week; mirror in `app_settings` |
