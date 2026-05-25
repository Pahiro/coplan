# CoPlan

Co-parenting scheduler for two parents — Flutter/Android app with a self-hosted PocketBase backend, a three-tier custody resolution engine, and home-screen widgets that update in the background.

---

## Features

- **Schedule resolution engine** — three-tier priority system: manual overrides → recurring weekday rules → week-rotation baseline
- **Custody requests** — day transfers and time-window handovers between parents, with transport direction tracking (who collects / who drops off)
- **One-off shared events** — ad-hoc events (birthday parties, school trips) visible to both parents regardless of whose week it is
- **Calendar views** — week strip and month grid with split-colour cells showing day transfers and ownership changes
- **Home-screen widgets** — three independently placeable Android Glance widget styles (Minimal, Material, Timeline), each showing the next 3 upcoming events; refreshed every 15 minutes via WorkManager
- **Local notifications** — new custody request alerts delivered even when the app is backgrounded
- **Offline queue** — mutations are queued locally when offline and replayed on reconnect

---

## Architecture

```
┌─────────────────────────────┐     HTTPS / PocketBase REST + SSE
│   Flutter App (Android)     │ ◄──────────────────────────────────► PocketBase LXC
│                             │                                        (Debian, Proxmox)
│  Riverpod providers         │                                           │
│  ResolutionEngine (Dart)    │                                        Cloudflared
│  WidgetCacheService         │                                        tunnel
│                             │                                           │
│  Android Glance Widgets ◄───┼── SharedPreferences ◄── WorkManager    Public URL
│  (3 styles)                 │   CoplanSyncWorker (Kotlin, 15 min)
└─────────────────────────────┘
```

### Backend — PocketBase

| Collection | Purpose |
|---|---|
| `users` | Two parent accounts (`Bennet`, `Jana`) |
| `rules_base` | Standing weekly schedule (day-of-week, time, activity, location) |
| `manual_overrides` | Date-specific parent substitutions and ad-hoc one-off events |
| `custody_weekday_rules` | Fixed recurring weekday overrides (higher priority than rotation) |
| `custody_requests` | Pending/accepted day-transfer and time-window handover requests; drives notifications |
| `app_settings` | Child colours and other key/value config |

### Resolution Engine

For any given event slot, the responsible parent is determined in priority order:

1. **Manual override** — date-specific record in `manual_overrides`
2. **Weekday rule** — recurring day-of-week record in `custody_weekday_rules`
3. **Week rotation** — even/odd weeks from a configurable Monday anchor (`ROTATION_ANCHOR`)

Accepted custody requests layer on top:
- **Day transfers** override day ownership from their pickup time onwards
- **Time windows** change responsibility only during the pickup → return interval

### Android Widget Sync

`CoplanSyncWorker` (Kotlin, WorkManager) runs every 15 minutes when a network connection is available. It independently reimplements the resolution engine in Kotlin — fetching base rules, weekday rules, manual overrides, and accepted custody requests from PocketBase, resolving the next 3 upcoming events, and writing them to `SharedPreferences` for all three Glance widget styles to read.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter 3, Material 3 |
| State | Riverpod (`AsyncNotifier`, `FutureProvider`) |
| Backend | PocketBase 0.22.22 |
| Backend host | Debian 12 LXC on Proxmox |
| Tunnel | Cloudflared (Cloudflare Tunnel) |
| Android widgets | Jetpack Glance (Compose-based) |
| Background sync | WorkManager (`PeriodicWorkRequest`, 15 min) |
| Notifications | `flutter_local_notifications` |
| Offline queue | Custom `QueueService` with `connectivity_plus` |

---

## Project Structure

```
lib/
├── core/
│   ├── constants.dart        # Build-time config (PB_URL, ROTATION_ANCHOR)
│   └── pb_client.dart        # Singleton PocketBase client
├── engine/
│   └── resolution_engine.dart  # Pure Dart schedule resolver
├── models/                   # Data classes (BaseRule, ManualOverride, CustodyRequest, …)
├── providers/                # Riverpod providers + notifiers
├── screens/                  # Dashboard, Calendar, Requests, Settings, Login
├── services/
│   ├── queue_service.dart    # Offline mutation queue
│   ├── notification_service.dart
│   └── widget_cache_service.dart  # Writes resolved events to SharedPreferences
└── widgets/                  # Reusable UI components

android/app/src/main/kotlin/com/coplan/app/
├── MainActivity.kt
├── CoplanWidget.kt           # Abstract base + 3 Glance widget styles
├── CoplanWidgetReceiver.kt   # BroadcastReceivers for all 3 styles
└── CoplanSyncWorker.kt       # WorkManager periodic sync (mirrors ResolutionEngine)

backend/
├── deploy.sh                 # One-shot server setup script
├── pb_migrations/            # PocketBase schema migrations
└── pb_hooks/                 # Server-side hooks (main.pb.js)
```

---

## Build & Deploy

See **[SETUP.md](SETUP.md)** for the full step-by-step guide. Quick reference:

### Android APK

```bash
flutter build apk --release \
  --dart-define=PB_URL=https://your-domain.com \
  --dart-define=ROTATION_ANCHOR=YYYY-MM-DD   # Monday of a known Bennet week
```

### Flutter Web (served by PocketBase)

```bash
flutter build web \
  --dart-define=PB_URL=https://your-domain.com \
  --dart-define=ROTATION_ANCHOR=YYYY-MM-DD

scp -r build/web/* user@server:/opt/coplan/pb_public/
```

### Server (Debian LXC)

```bash
# Copy backend/ to the server, then:
bash backend/deploy.sh
```

`deploy.sh` installs PocketBase to `/opt/coplan/`, applies migrations, creates a `coplan` system user, and registers a systemd service.

### Build flags

| Flag | Default | Description |
|---|---|---|
| `PB_URL` | `http://localhost:8090` | PocketBase server URL |
| `ROTATION_ANCHOR` | `2026-05-18` | Monday of a week where Bennet had the children |

---

## Adding the Home-Screen Widget (Android)

1. Long-press the home screen → **Widgets**
2. Find **CoPlan** — three styles are available:
   - **CoPlan – Minimal** (dark, accent bar)
   - **CoPlan – Material** (dark, rounded date token)
   - **CoPlan – Timeline** (adaptive, node + connecting line)
3. Place any or all of them; they all read from the same data source and refresh every 15 minutes automatically

---

## Rotation Anchor

The week-rotation baseline alternates ownership week by week from a fixed Monday. Set `ROTATION_ANCHOR` to any Monday when Bennet had the children. The parity of weeks elapsed from that anchor determines who owns each subsequent week (even = Bennet, odd = Jana).

To recalculate after a schedule change, find a new reference Monday and rebuild with the updated `--dart-define=ROTATION_ANCHOR=YYYY-MM-DD`.
