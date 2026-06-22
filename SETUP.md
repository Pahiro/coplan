# CoPlan — Setup Guide

## What lives where

| Layer | Technology | Host |
|---|---|---|
| Backend + DB | PocketBase (single binary) | Proxmox LXC (Debian) |
| Tunnel | Cloudflared | Same LXC |
| Web app | Flutter web build | Served by PocketBase static files |
| Android app | Flutter APK | Sideloaded or distributed manually |
| Push notifications | FCM (server-side) + PocketBase SSE for foreground | `coplan-push` Node sidecar on the LXC |
| Dev / testing | PocketBase + `flutter run -d chrome` | Windows workstation |

---

## Part 1 — What you can configure without touching code

Everything below is editable through the **PocketBase admin UI** at `http://<host>:8090/_/`
or via the **CoPlan app** itself once installed.

| What | Where in admin UI | Notes |
|---|---|---|
| User accounts (Father, Mother) | Collections → users | Set `name` to exactly `"Father"` or `"Mother"` |
| Parent preferred colour | Collections → users → record | Field `preferred_color` e.g. `#1565C0` |
| Child colours (Child 1, Child 2) | Collections → app_settings | Keys `color_child1`, `color_child2` |
| Base schedule rules | Collections → rules_base | Times, locations, activities, default parent |
| Manual overrides | Collections → manual_overrides | One record per date override |
| Pickup requests | Collections → pickup_requests | Visible to both parents |

### Two values that require a build flag (set once, forget it)

```bash
# Example — production build
flutter build apk \
  --dart-define=PB_URL=https://coplan.yourdomain.com \
  --dart-define=ROTATION_ANCHOR=2026-05-18

# ROTATION_ANCHOR must be the Monday of a week where the Father had the kids.
# Default is 2026-05-18 if omitted.
# PB_URL defaults to http://localhost:8090 for local dev.
```

### Firebase config for Android builds (not in git)

`android/app/google-services.json` is **gitignored** (it holds the Android
client API key). Before building the APK, download it from the Firebase
console → project **coplan-23f80** → Project settings → your Android app
(`com.coplan.app`) → `google-services.json`, and place it at
`android/app/google-services.json`. Push setup also needs the FCM service-account
key on the server — see `backend/push-sidecar/README.md`.

---

## Part 2 — Local development (Windows)

### Prerequisites
- Flutter SDK (stable channel): https://docs.flutter.dev/get-started/install/windows
- Chrome (for web target)
- PocketBase Windows binary (downloaded below)

### 2a — Run PocketBase locally

Open PowerShell **in a dedicated folder**, e.g. `C:\coplan-dev\`:

```powershell
# Download and extract
curl -L "https://github.com/pocketbase/pocketbase/releases/download/v0.22.22/pocketbase_0.22.22_windows_amd64.zip" -o pb.zip
Expand-Archive pb.zip .

# Copy the migration and hook files from the repo
Copy-Item -Recurse C:\Projects\CoParent\backend\pb_migrations .\pb_migrations
Copy-Item -Recurse C:\Projects\CoParent\backend\pb_hooks .\pb_hooks

# Start PocketBase (runs migrations automatically on first launch)
.\pocketbase.exe serve
```

Open **http://localhost:8090/_/** → create your admin account.

### 2b — Seed user accounts

In the admin UI:

1. Collections → **users** → **+ New record**
   - `email`: `father@coplan.local`
   - `password`: anything (8+ chars)
   - `name`: `Father`
   - `preferred_color`: `#1565C0` (or leave blank for default)
2. Repeat for the Mother:
   - `email`: `mother@coplan.local`
   - `name`: `Mother`
   - `preferred_color`: `#D81B60`

### 2c — Run the Flutter web app

```bash
cd C:\Projects\CoParent\coplan
flutter pub get
flutter run -d chrome
# PB_URL defaults to http://localhost:8090 — no flags needed for local dev
```

---

## Part 3 — Production deployment on Debian LXC

### 3a — Create the LXC

In Proxmox, create a Debian 12 LXC container. Minimum specs:
- 1 CPU core, 512 MB RAM, 4 GB disk
- Network: bridged with a static IP or DHCP reservation

SSH into the container, then:

```bash
# Update and install dependencies
apt-get update && apt-get install -y curl unzip

# Clone or copy the backend folder from your Windows machine
# e.g. via scp:
# scp -r C:\Projects\CoParent\backend root@<lxc-ip>:/root/coplan-backend

cd /root/coplan-backend
bash deploy.sh
```

`deploy.sh` will:
- Download PocketBase to `/opt/coplan/`
- Copy migrations and hooks
- Create a `coplan` system user
- Install and start a **systemd service** (`coplan.service`)

Verify it's running:
```bash
systemctl status coplan
# Should show: Active: active (running)

curl http://localhost:8090/api/health
# {"code":200,"message":"API is healthy.","data":{}}
```

### 3b — First run: create admin account

```bash
# Port-forward temporarily from your Windows machine to access the admin UI
ssh -L 8090:localhost:8090 root@<lxc-ip>
```

Open **http://localhost:8090/_/** on your Windows machine → create admin account → verify the `rules_base` collection was seeded with the schedule rules.

Then **create user accounts** (same as §2b above).

### 3c — Serve the Flutter web build

Build the web app on your Windows machine:

```bash
cd C:\Projects\CoParent\coplan
flutter build web \
  --dart-define=PB_URL=https://coplan.yourdomain.com \
  --dart-define=ROTATION_ANCHOR=2026-05-18 \
  --dart-define=NTFY_URL=https://ntfy.yourserver.com
```

Copy the output to the LXC:

```bash
scp -r build\web\* root@<lxc-ip>:/opt/coplan/pb_public/
```

PocketBase automatically serves any files in `pb_public/` as a static site. The web app will be accessible at `https://coplan.yourdomain.com`.

---

## Part 4 — Cloudflared tunnel

On the LXC (assuming you already have a Cloudflare account and `cloudflared` installed):

```bash
# Install cloudflared
curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" -o cloudflared.deb
dpkg -i cloudflared.deb

# Authenticate (follow the URL printed)
cloudflared tunnel login

# Create a tunnel
cloudflared tunnel create coplan

# Route your domain to it
cloudflared tunnel route dns coplan coplan.yourdomain.com

# Create config
mkdir -p /etc/cloudflared
cat > /etc/cloudflared/config.yml << EOF
tunnel: coplan
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: coplan.yourdomain.com
    service: http://localhost:8090
  - service: http_status:404
EOF

# Install as system service
cloudflared service install
systemctl enable --now cloudflared
```

---

## Part 5 — Push notifications

CoPlan uses PocketBase's built-in real-time SSE (Server-Sent Events) — no extra
notification server required.

**How it works:**
- When the app is open (foreground): a heads-up banner appears inside the app.
- When the app is backgrounded (Android): the OS shows a notification in the
  notification shade. Android 13+ will prompt for notification permission on first launch.
- When the app is fully closed: no notification is delivered (acceptable trade-off
  for a two-person app where both users keep the app running).

**No phone setup required** — notifications work automatically once the app is
installed and logged in. No separate ntfy app, topic subscriptions, or server
configuration needed.

---

## Part 6 — Android APK

```bash
cd C:\Projects\CoParent\coplan
flutter build apk \
  --dart-define=PB_URL=https://coplan.yourdomain.com \
  --dart-define=ROTATION_ANCHOR=2026-05-18
```

Output: `build\app\outputs\flutter-apk\app-release.apk`

Transfer to each phone and install. You may need to enable **"Install from unknown sources"** in Android settings.

### Android widget setup
After installing the APK, long-press the home screen → Widgets → find **CoPlan** → add the
4×2 widget. It shows the next 3 upcoming events and **updates every 30 minutes in the
background** via WorkManager — no need to open the app.

The Android project is fully scaffolded. All required Gradle dependencies (WorkManager, Glance, desugaring) are already in `android/app/build.gradle.kts`. No manual additions needed.

---

## Part 7 — Ongoing maintenance

### Updating the standing schedule
Open the admin UI → Collections → `rules_base` → edit any record.

Each rule has these fields:

| Field | Description |
|---|---|
| `child_name` | `Henri`, `Chris`, or `All` |
| `day_of_week` | 1 = Monday … 7 = Sunday |
| `event_time` | `HH:MM` 24-hour |
| `activity` | Display name of the event |
| `location` | Where it takes place |
| `is_shared` | **true** = both parents see this event regardless of whose week it is (e.g. rugby practice, swimming lessons) |

> **No `default_parent` field** — the responsible parent is always determined by the resolution engine (override → fixed weekday → week rotation). There is no default parent on a rule.

### Marking a standing event as shared
In `rules_base`, set `is_shared = true` on any rule that is a regular obligation both parents need to know about. The app will tag it with a **"Both"** badge and still show which parent is responsible for transport that day.

### Adding a one-off shared event (birthday party, school trip, etc.)
Use the app: Dashboard → **New request** → tap **Shared event** tab.

Fill in the date, time, event name, and location. The app automatically shows which parent has the kids that day — they become responsible for transport. The event appears in both parents' views with a **"Both"** badge.

Alternatively, via the admin UI → `manual_overrides` → New record:
- `is_adhoc = true`
- `is_shared = true`
- `assigned_parent` = the parent responsible for transport

### Adding a custody reassignment override (e.g. "Jana working late Friday")
Either:
- Use the app (Dashboard → **New request** → Custody → Pickup/Drop-off/Handover), or
- Admin UI → Collections → `manual_overrides` → New record with `is_adhoc = false`

### Updating PocketBase
```bash
# On the LXC
systemctl stop coplan
# Download new binary to /opt/coplan/pocketbase
systemctl start coplan
```

### Rotation anchor
If you ever need to recalculate the rotation anchor (e.g. after a schedule swap):
1. Find any Monday where Bennet had the kids
2. Rebuild the app with `--dart-define=ROTATION_ANCHOR=YYYY-MM-DD`
3. Rebuild and redeploy the web app + APK

---

## Quick-reference: all build flags

| Flag | Default | Description |
|---|---|---|
| `PB_URL` | `http://localhost:8090` | PocketBase server URL |
| `ROTATION_ANCHOR` | `2026-05-18` | Monday of a known Bennet week |
