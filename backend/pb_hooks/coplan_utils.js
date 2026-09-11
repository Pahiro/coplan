// Shared helpers for main.pb.js.
//
// PocketBase v0.22 runs every hook, route and cron handler in its own isolated
// context, so functions declared at the top level of main.pb.js are NOT
// visible inside handlers (calls fail with "ReferenceError: … is not defined").
// Load this module inside each handler instead:
//
//   const u = require(`${__hooks}/coplan_utils.js`);
//
// The file name doesn't end in .pb.js, so PocketBase doesn't load it as hooks.

const DAY_NAMES   = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// "2026-09-13" → "Sat 13 Sep". Falls back to the input when unparseable.
function fmtDay(s) {
    const p = String(s || "").slice(0, 10).split("-");
    if (p.length !== 3) return String(s || "");
    const d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2]));
    if (isNaN(d.getTime())) return String(s || "");
    return `${DAY_NAMES[d.getUTCDay()]} ${d.getUTCDate()} ${MONTH_NAMES[d.getUTCMonth()]}`;
}

// "YYYY-MM-DD" for a Date, in server-local time.
function isoLocal(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

// Display name of a user within a household, or "".
function memberName(dao, householdId, userId) {
    if (!householdId || !userId) return "";
    try {
        return dao.findFirstRecordByFilter(
            "household_members", "household = {:h} && user = {:u}",
            { h: householdId, u: userId }
        ).get("display_name") || "";
    } catch (_) { return ""; }
}

// "All" → "the kids", "Henri,Chris" → "Henri & Chris".
function kids(childName) {
    if (!childName || childName === "All") return "the kids";
    const parts = String(childName).split(",").map((s) => s.trim()).filter(Boolean);
    if (parts.length <= 1) return String(childName);
    return `${parts.slice(0, -1).join(", ")} & ${parts[parts.length - 1]}`;
}

// Both legs of a day swap, sorted by date.
function swapLegs(dao, group) {
    if (!group) return [];
    try {
        return dao.findRecordsByFilter("custody_requests", "swap_group = {:g}", "date", 10, 0, { g: group });
    } catch (_) { return []; }
}

function money(cents) {
    return `R ${((Number(cents) || 0) / 100).toFixed(2)}`;
}

function expenseTitle(dao, expenseId) {
    if (!expenseId) return "a shared expense";
    try { return dao.findRecordById("shared_expenses", expenseId).get("title") || "a shared expense"; }
    catch (_) { return "a shared expense"; }
}

// ── Push (FCM via the coplan-push sidecar) ───────────────────────────────────
//
// The sidecar (loopback, 127.0.0.1:8091) does the actual FCM HTTP v1 send
// because PocketBase's JS engine can't mint the RS256 OAuth token Google
// requires. We look up the recipients' device tokens, POST them to the
// sidecar, and prune any tokens it reports as dead.

const PUSH_URL = "http://127.0.0.1:8091/send";

// Send a push to one or more user ids. Never throws — a push failure must not
// break the record write that triggered it.
function sendPush(dao, userIds, title, body, data) {
    try {
        const secret = $os.getenv("PUSH_SECRET");
        if (!secret) { console.log("sendPush: PUSH_SECRET not set, skipping:", title); return; }

        const ids = (Array.isArray(userIds) ? userIds : [userIds]).filter(Boolean);
        if (ids.length === 0) return;

        const tokens = [];
        for (const uid of ids) {
            let rows = [];
            try { rows = dao.findRecordsByFilter("device_tokens", "user = {:u}", "", 50, 0, { u: uid }); }
            catch (_) { rows = []; }
            for (const r of rows) { const t = r.get("token"); if (t) tokens.push(t); }
        }
        if (tokens.length === 0) return;

        const res = $http.send({
            url:     PUSH_URL,
            method:  "POST",
            timeout: 10,
            headers: { "content-type": "application/json", "x-push-secret": secret },
            body:    JSON.stringify({ tokens, title, body, data: data || {} }),
        });

        if (res.statusCode !== 200) {
            console.log("sendPush: sidecar returned", res.statusCode, res.raw);
            return;
        }

        const results = (res.json && res.json.results) || [];
        for (const r of results) {
            if (!r.invalid) continue;
            try {
                const dead = dao.findFirstRecordByFilter("device_tokens", "token = {:t}", { t: r.token });
                dao.deleteRecord(dead);
            } catch (_) {}
        }
    } catch (err) {
        console.log("sendPush error:", err);
    }
}

module.exports = { fmtDay, isoLocal, memberName, kids, swapLegs, money, expenseTitle, sendPush };
