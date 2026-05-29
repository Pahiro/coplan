#!/bin/bash
#
# deploy.sh — Full CoPlan deployment script
#
# Usage:
#   ./deploy.sh [--skip-build] [--skip-apk] [--skip-backend] [--skip-web]
#
# Prerequisites:
#   - SSH key access to root@192.168.1.119
#   - Flutter SDK in PATH
#   - PB_URL defaults to https://coplan.vdgryp.co.za
#

set -euo pipefail

SERVER="root@192.168.1.119"
PB_DIR="/opt/coplan"
PB_URL="${PB_URL:-https://coplan.vdgryp.co.za}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse flags
SKIP_BUILD=false
SKIP_APK=false
SKIP_BACKEND=false
SKIP_WEB=false

for arg in "$@"; do
    case $arg in
        --skip-build)   SKIP_BUILD=true ;;
        --skip-apk)     SKIP_APK=true ;;
        --skip-backend) SKIP_BACKEND=true ;;
        --skip-web)     SKIP_WEB=true ;;
        --help|-h)
            echo "Usage: ./deploy.sh [--skip-build] [--skip-apk] [--skip-backend] [--skip-web]"
            exit 0 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $1"; }
err()   { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

# Extract version from pubspec.yaml (tr -d strips any Windows \r)
get_version() {
    grep '^version:' "$SCRIPT_DIR/pubspec.yaml" | sed 's/version: //' | tr -d '\r\n '
}
get_version_name() {
    get_version | sed 's/+.*//'
}
get_version_code() {
    get_version | sed 's/.*+//'
}

# Bump the build number (versionCode) in pubspec.yaml.
# e.g. 1.0.5+6 → 1.0.5+7.  Pass --bump-minor to also bump the minor:
# 1.0.5+6 → 1.0.6+7.
bump_version() {
    local old_version
    old_version=$(get_version)
    local name="${old_version%+*}"     # e.g. 1.0.5
    local code="${old_version##*+}"    # e.g. 6
    local new_code=$((code + 1))

    local major minor patch
    IFS='.' read -r major minor patch <<< "$name"
    local new_name="$major.$minor.$((patch + 1))"

    local new_version="$new_name+$new_code"
    sed -i "s/^version: .*/version: $new_version/" "$SCRIPT_DIR/pubspec.yaml"
    # Also strip any trailing \r that sed -i may have left
    sed -i 's/\r$//' "$SCRIPT_DIR/pubspec.yaml"
    info "Version bumped: $old_version → $new_version"
}

# ── 1. Bump version ──────────────────────────────────────────────────────────

if [ "$SKIP_BUILD" = false ]; then
    bump_version
fi

# ── 2. Backend: backup, deploy migrations + hooks ────────────────────────────

if [ "$SKIP_BACKEND" = false ]; then
    info "Deploying backend (migrations + hooks)..."
    info "Backing up PocketBase data..."
    ssh "$SERVER" "systemctl stop coplan && tar czf /root/coplan-backups/pb_data-\$(date +%Y%m%d-%H%M%S).tar.gz -C $PB_DIR pb_data"
    ok "Backup created"

    info "Copying migrations..."
    scp "$SCRIPT_DIR"/backend/pb_migrations/*.js "$SERVER:$PB_DIR/pb_migrations/"
    ok "Migrations copied"

    info "Copying hooks..."
    scp "$SCRIPT_DIR/backend/pb_hooks/main.pb.js" "$SERVER:$PB_DIR/pb_hooks/main.pb.js"
    ok "Hooks copied"

    info "Starting PocketBase and verifying..."
    ssh "$SERVER" "systemctl start coplan && sleep 4 && curl -sf http://localhost:8090/api/health > /dev/null"
    ok "PocketBase healthy"

    # Check for hook/migration errors
    ERRORS=$(ssh "$SERVER" "journalctl -u coplan -n 20 --no-pager 2>/dev/null | grep -i 'error\|failed' || true")
    if [ -n "$ERRORS" ]; then
        echo -e "\033[1;33m[WARN]\033[0m Possible errors in logs:"
        echo "$ERRORS"
    fi
else
    info "Skipping backend deployment"
fi

# ── 3. Build APK ─────────────────────────────────────────────────────────────

if [ "$SKIP_BUILD" = false ] && [ "$SKIP_APK" = false ]; then
    info "Building release APK..."
    flutter build apk --release --dart-define=PB_URL="$PB_URL"
    ok "APK built: build/app/outputs/flutter-apk/app-release.apk"
fi

# ── 4. Deploy APK + update app_settings ──────────────────────────────────────

if [ "$SKIP_APK" = false ]; then
    VERSION_NAME=$(get_version_name)
    VERSION_CODE=$(get_version_code)
    APK_PATH="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-release.apk"

    if [ ! -f "$APK_PATH" ]; then
        err "APK not found at $APK_PATH — run without --skip-build"
    fi

    info "Deploying APK (v$VERSION_NAME+$VERSION_CODE)..."
    scp "$APK_PATH" "$SERVER:$PB_DIR/pb_public/coplan-latest.apk"
    ok "APK uploaded"

    info "Updating app_settings (version $VERSION_NAME, build $VERSION_CODE)..."
    APK_URL="$PB_URL/coplan-latest.apk?v=$VERSION_CODE"
    ssh "$SERVER" "sqlite3 $PB_DIR/pb_data/data.db \"
        UPDATE app_settings SET value = '$VERSION_CODE'  WHERE key = 'latest_build';
        UPDATE app_settings SET value = '$VERSION_NAME'  WHERE key = 'latest_version';
        UPDATE app_settings SET value = '$APK_URL'       WHERE key = 'apk_url';
    \""
    ok "app_settings updated"

    info "Verifying Cloudflare cache-bust..."
    HTTP_STATUS=$(curl -sI "${APK_URL}" | grep -i "cf-cache-status" || echo "unknown")
    echo "  $HTTP_STATUS"
    ok "APK deployment complete"
else
    info "Skipping APK deployment"
fi

# ── 5. Build + deploy web ─────────────────────────────────────────────────────

if [ "$SKIP_WEB" = false ]; then
    if [ "$SKIP_BUILD" = false ]; then
        info "Building web..."
        flutter build web --dart-define=PB_URL="$PB_URL"
        ok "Web built"
    fi

    info "Deploying web to pb_public (alongside APK)..."
    # Copy web build into pb_public root, preserving the existing APK
    scp -r "$SCRIPT_DIR/build/web/"* "$SERVER:$PB_DIR/pb_public/"
    ok "Web deployed to $PB_URL/"
else
    info "Skipping web deployment"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

VERSION_NAME=$(get_version_name)
VERSION_CODE=$(get_version_code)
echo ""
ok "Deployment complete! Version: $VERSION_NAME+$VERSION_CODE"
echo "  APK: $PB_URL/coplan-latest.apk?v=$VERSION_CODE"
echo "  Web: $PB_URL/"
