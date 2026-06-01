# CLAUDE.md — operational guide for working on CoPlan

Read this first. It captures the conventions, infra, and gotchas that aren't
obvious from the code. For architecture/features see `README.md`; for first-time
deployment see `SETUP.md`.

CoPlan is a co-parenting scheduler: Flutter app (Android + web) + self-hosted
PocketBase. The live household is Bennet & Jana; the app is multi-household.

## Infra / server

- **PocketBase LXC**: `root@192.168.1.119` (Debian, Proxmox). Runs from
  `/opt/coplan/` as systemd service **`coplan`**. PocketBase **v0.22.22**.
- **Public URL**: `https://coplan.vdgryp.co.za` via a **Cloudflare tunnel**.
- **DB**: SQLite at `/opt/coplan/pb_data/data.db` (read directly with `sqlite3`).
- **Static files**: `/opt/coplan/pb_public/` is served at the domain root.
- **Backups**: `/root/coplan-backups/`. **Always back up before a migration.**
- Migrations live in `/opt/coplan/pb_migrations/`, hooks in
  `/opt/coplan/pb_hooks/main.pb.js`. They auto-apply / reload on service start.
- ⚠️ The server's migration set has **drifted** from the repo (admin-UI-generated
  migrations exist server-side; some repo migrations were applied manually).
  Always check `_migrations` on the server before assuming state.

## Build / run

```bash
# Android (rotation config is per-household now — no ROTATION_ANCHOR flag)
flutter build apk --release --dart-define=PB_URL=https://coplan.vdgryp.co.za
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Web
flutter build web --dart-define=PB_URL=https://coplan.vdgryp.co.za

flutter test     # pure-Dart engine/model unit tests live in test/
flutter analyze  # a few pre-existing lint warnings are expected
```

## Resolution engine — the heart of the app

- `lib/engine/resolution_engine.dart` is **pure Dart and the single source of
  truth**. Every UI surface builds an engine and asks it.
- Priority: manual override → weekday rule → rotation; accepted custody requests
  + recurring arrangements layer on by time of day.
- Parents are **strings** (display names), not an enum. Rotation is
  **pattern-based per household** (`RotationScheme`) using **UTC epoch math**.
- The same logic is reimplemented in **two other places that must stay in sync**:
  - Kotlin `CoplanSyncWorker.kt` (home-screen widgets).
  - JS `freezeRecurring` cron in `pb_hooks/main.pb.js` (freezes past recurring
    occurrences into immutable history).
  Change one → update all three.

## Security model (household-scoped) — IMPORTANT

Access rules restrict every collection to **members of the record's household**
(migration `1779400008`). Consequences when writing code:

- **Every create MUST stamp `household`** (the active household id), or the
  hardened `createRule` denies it. Applies to rules_base, manual_overrides,
  custody_requests, custody_recurring, custody_weekday_rules, children.
- Membership filter (PB v0.22 back-relation):
  `household.household_members_via_household.user ?= @request.auth.id`.
- **Invite redemption is server-side**: `POST /api/coplan/accept-invite`
  (pb_hooks) runs with DAO privileges because a joiner isn't a member yet and
  can't read the invite or self-create membership. Don't move it back to the
  client. Invites are not enumerable.
- Households have an **`owner`** (can remove members / transfer ownership).
- Registration is intentionally open; the household boundary is what contains
  access.

## PocketBase migrations — conventions (v0.22!)

- Use the **classic v0.22 API**: `migrate((db) => { const dao = new Dao(db); … })`.
  **NOT** the v0.23 `migrate((app) => app.dao())` form — it fails on this server
  with "Object has no member 'dao'".
- `findRecordsByFilter` **rejects an empty filter** — use `"id != ''"` for "all".
- Name new migrations with a **timestamp above the server's latest applied**
  one (we've been using the `17794000xx` range).
- Always include a working **down** migration.
- ⚠️ **Committing a migration to git does NOT deploy it.** You must `scp` it to
  the server and restart, then confirm it's in `_migrations` AND that the
  intended rules/fields actually changed (`sqlite3 … _collections`). A migration
  that's committed but never deployed silently leaves the server on the old
  state — this caused a real cross-household data leak (the access-control rules
  were committed but never ran on the box). For access-control changes,
  always verify with a throwaway account that it can't read another household.

## Deploying backend changes (migration / hook)

```bash
# 1. Back up first
ssh root@192.168.1.119 "systemctl stop coplan && tar czf /root/coplan-backups/pb_data-$(date +%Y%m%d-%H%M%S).tar.gz -C /opt/coplan pb_data"
# 2. Copy files
scp backend/pb_migrations/<file>.js root@192.168.1.119:/opt/coplan/pb_migrations/
scp backend/pb_hooks/main.pb.js     root@192.168.1.119:/opt/coplan/pb_hooks/main.pb.js
# 3. Start + verify (migration applied, no hook errors, health 200)
ssh root@192.168.1.119 "systemctl start coplan && sleep 4 && curl -s http://localhost:8090/api/health && journalctl -u coplan -n 15 --no-pager | grep -i error"
```

## Publishing an app update (the in-app updater)

The app shows an "Update available" banner by comparing its build number to
`app_settings` keys. To release, run **`./deploy.sh`** from the repo root
(handles version bump, build, backend, APK upload, `app_settings`, and web in
one shot). Manual equivalent:

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.4+5` → versionCode 5).
2. `flutter build apk --release --dart-define=PB_URL=https://coplan.vdgryp.co.za`
3. `scp …/app-release.apk root@192.168.1.119:/opt/coplan/pb_public/coplan-latest.apk`
4. Update `app_settings` (sqlite or admin UI):
   - `latest_build` = new versionCode
   - `latest_version` = display version
   - `apk_url` = `https://coplan.vdgryp.co.za/coplan-latest.apk?v=<build>`
   - `update_notes` = short user-facing release notes (shown in the update banner)
   - ⚠️ **Always set `update_notes`** — the banner shows whatever is in this field,
     so leaving it stale means users see notes from a previous release.
5. ⚠️ **Cloudflare caches the APK** at a reused URL — *must* cache-bust. The
   `?v=<build>` query is required (and the client also appends its own
   cache-bust param from build 5+). Verify with
   `curl -sI "…/coplan-latest.apk?v=<build>"` → `cf-cache-status: MISS`.

## Widgets (Android home-screen, Glance)

- Three styles, three receivers: `CoplanWidgetReceiver`, `CoplanWidget2Receiver`,
  `CoplanWidget3Receiver`. `WidgetCacheService.updateCache()` must redraw **all
  three** (broadcast to each receiver) — updating only one leaves the others
  stale.
- The 15-min `CoplanSyncWorker` is **frequently deferred by Doze**, so the app's
  on-open/on-resume cache refresh is the reliable path. Don't rely on the worker
  alone.

## Workflow notes

- GitHub: `https://github.com/Pahiro/coplan.git`. Commit/push when the user asks.
- A stored git credential (`~/.git-credentials`) can drive the GitHub API
  (issues, etc.) for this repo.
- The Android `versionCode` comes from pubspec `+<n>`; `adb shell dumpsys
  package com.coplan.app | grep version` shows what's installed.
