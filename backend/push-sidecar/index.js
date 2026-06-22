// coplan-push — a tiny loopback FCM sender.
//
// Why this exists: PocketBase's JS engine can only sign HS256 JWTs, but the
// FCM HTTP v1 API requires a Google OAuth2 access token minted from an RS256
// service-account key. firebase-admin handles that token minting + refresh.
// The PocketBase hook POSTs here over loopback; this process talks to Google.
//
// Security: binds to 127.0.0.1 only and requires a shared secret header, so it
// is not reachable off-box and not callable by other local processes blindly.
//
// Env:
//   PUSH_PORT             listen port            (default 8091)
//   PUSH_SECRET           required shared secret (must match the PB hook)
//   GOOGLE_APPLICATION_CREDENTIALS  path to the service-account JSON
//
// API:
//   GET  /health                      -> { ok: true }
//   POST /send  { tokens[], title, body, data? }
//        header  x-push-secret: <PUSH_SECRET>
//        -> { successCount, failureCount, results: [{ token, success, invalid, error }] }
//
// `invalid: true` flags tokens the caller should delete (unregistered / bad).

const http = require("http");
const admin = require("firebase-admin");

const PORT = parseInt(process.env.PUSH_PORT || "8091", 10);
const SECRET = process.env.PUSH_SECRET || "";
const CREDS = process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!SECRET) {
  console.error("FATAL: PUSH_SECRET is not set");
  process.exit(1);
}
if (!CREDS) {
  console.error("FATAL: GOOGLE_APPLICATION_CREDENTIALS is not set");
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(CREDS)),
});

// FCM error codes that mean the token is permanently dead and should be pruned.
const DEAD_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => {
      data += c;
      if (data.length > 1_000_000) reject(new Error("body too large"));
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

async function handleSend(req, res, payload) {
  const tokens = Array.isArray(payload.tokens) ? payload.tokens.filter(Boolean) : [];
  const title = String(payload.title || "CoPlan");
  const body = String(payload.body || "");
  const data = payload.data && typeof payload.data === "object" ? payload.data : {};

  if (tokens.length === 0) {
    return json(res, 200, { successCount: 0, failureCount: 0, results: [] });
  }

  // All data values must be strings for FCM.
  const stringData = {};
  for (const [k, v] of Object.entries(data)) stringData[k] = String(v);

  const message = {
    tokens,
    notification: { title, body },
    data: stringData,
    android: {
      priority: "high",
      notification: { channelId: "coplan_requests" },
    },
  };

  const resp = await admin.messaging().sendEachForMulticast(message);
  const results = resp.responses.map((r, i) => ({
    token: tokens[i],
    success: r.success,
    invalid: !r.success && r.error && DEAD_CODES.has(r.error.code),
    error: r.success ? null : (r.error && r.error.code) || "unknown",
  }));

  return json(res, 200, {
    successCount: resp.successCount,
    failureCount: resp.failureCount,
    results,
  });
}

function json(res, code, obj) {
  const s = JSON.stringify(obj);
  res.writeHead(code, { "content-type": "application/json" });
  res.end(s);
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/health") {
      return json(res, 200, { ok: true });
    }
    if (req.method === "POST" && req.url === "/send") {
      if (req.headers["x-push-secret"] !== SECRET) {
        return json(res, 403, { error: "forbidden" });
      }
      const raw = await readBody(req);
      let payload = {};
      try { payload = JSON.parse(raw || "{}"); }
      catch { return json(res, 400, { error: "invalid json" }); }
      return await handleSend(req, res, payload);
    }
    return json(res, 404, { error: "not found" });
  } catch (err) {
    console.error("send error:", err);
    return json(res, 500, { error: String((err && err.message) || err) });
  }
});

// Loopback only — never expose this off-box.
server.listen(PORT, "127.0.0.1", () => {
  console.log(`coplan-push listening on 127.0.0.1:${PORT}`);
});
