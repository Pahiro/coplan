# coplan-push — FCM sidecar

A ~150-line Node service that sends FCM HTTP v1 push notifications on behalf of
PocketBase. PocketBase's JS engine can only sign HS256 JWTs; FCM v1 needs an
RS256 service-account token. firebase-admin handles that here.

PocketBase hooks call it over loopback (`http://127.0.0.1:8091/send`), guarded
by a shared secret. It is never exposed off-box.

## One-time install on the server (192.168.1.219)

```bash
# 1. Copy the code
ssh root@192.168.1.219 "mkdir -p /opt/coplan-push"
scp backend/push-sidecar/index.js backend/push-sidecar/package.json \
    root@192.168.1.219:/opt/coplan-push/

# 2. Drop in the service-account key (Firebase console -> Project settings ->
#    Service accounts -> Generate new private key). NEVER commit this file.
scp ~/Downloads/coplan-23f80-*.json root@192.168.1.219:/opt/coplan-push/service-account.json
ssh root@192.168.1.219 "chmod 600 /opt/coplan-push/service-account.json"

# 3. Install deps
ssh root@192.168.1.219 "cd /opt/coplan-push && npm install --omit=dev"

# 4. Install the systemd unit + the secret (must match PB hook's PUSH_SECRET)
scp backend/push-sidecar/coplan-push.service root@192.168.1.219:/etc/systemd/system/
ssh root@192.168.1.219 "mkdir -p /etc/systemd/system/coplan-push.service.d && \
  printf '[Service]\nEnvironment=PUSH_SECRET=%s\n' \"$PUSH_SECRET\" \
    > /etc/systemd/system/coplan-push.service.d/secret.conf && \
  chmod 600 /etc/systemd/system/coplan-push.service.d/secret.conf && \
  systemctl daemon-reload && systemctl enable --now coplan-push"

# 5. Verify
ssh root@192.168.1.219 "curl -s http://127.0.0.1:8091/health && systemctl status coplan-push --no-pager | head -5"
```

The **same** `PUSH_SECRET` must be set for the PocketBase service so the hook can
authenticate. Set it on the `coplan` unit the same way (`systemctl edit coplan`
-> `Environment=PUSH_SECRET=...`), since the hook reads it via `$os.getenv`.

## Test

```bash
ssh root@192.168.1.219 'curl -s -X POST http://127.0.0.1:8091/send \
  -H "x-push-secret: $PUSH_SECRET" -H "content-type: application/json" \
  -d "{\"tokens\":[\"<a-real-device-token>\"],\"title\":\"Test\",\"body\":\"hi\"}"'
```
