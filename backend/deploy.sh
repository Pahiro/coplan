#!/usr/bin/env bash
# CoPlan — PocketBase deployment script
# Run this script inside your Proxmox LXC container (Debian/Ubuntu).
# Usage: sudo bash deploy.sh

set -euo pipefail

PB_VERSION="0.22.22"
INSTALL_DIR="/opt/coplan"
SERVICE_USER="coplan"
NTFY_URL="${NTFY_URL:-https://ntfy.yourserver.com}"   # override before running

# ── Detect architecture ───────────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  PB_ARCH="linux_amd64"  ;;
  aarch64) PB_ARCH="linux_arm64"  ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

echo "==> Creating system user and directories"
id "$SERVICE_USER" &>/dev/null || useradd --system --no-create-home --shell /bin/false "$SERVICE_USER"
mkdir -p "$INSTALL_DIR"/{pb_data,pb_migrations,pb_hooks}

echo "==> Downloading PocketBase v${PB_VERSION} (${PB_ARCH})"
curl -fsSL \
  "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_${PB_ARCH}.zip" \
  -o /tmp/pb.zip
apt-get install -y --no-install-recommends unzip > /dev/null
unzip -o /tmp/pb.zip pocketbase -d "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/pocketbase"
rm /tmp/pb.zip

echo "==> Copying migrations and hooks"
cp -r pb_migrations/. "$INSTALL_DIR/pb_migrations/"
cp -r pb_hooks/.      "$INSTALL_DIR/pb_hooks/"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

echo "==> Writing systemd service"
cat > /etc/systemd/system/coplan.service << EOF
[Unit]
Description=CoPlan PocketBase
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/pocketbase serve --http=127.0.0.1:8090
Environment=NTFY_URL=${NTFY_URL}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now coplan

echo ""
echo "✓ PocketBase is running on http://127.0.0.1:8090"
echo "✓ Admin UI:  http://127.0.0.1:8090/_/"
echo ""
echo "Next steps:"
echo "  1. Open the admin UI and create two user accounts (bennet@ and jana@)"
echo "  2. Configure Cloudflared to tunnel to 127.0.0.1:8090"
echo "     cloudflared tunnel route dns <tunnel-name> coplan.yourdomain.com"
echo "  3. Update lib/core/constants.dart in the Flutter app with your tunnel URL"
echo "  4. Each phone subscribes to ntfy topic: coplan-<their PocketBase user ID>"
