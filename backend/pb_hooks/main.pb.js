/// <reference path="../pb_data/types.d.ts" />

// Notifications: in-app banners + foreground alerts are still driven by the
// Flutter realtime (SSE) subscriptions, but reliable OS-level / background push
// is delivered server-side from here via FCM (see the "Push notifications"
// section at the bottom of this file). The two cooperate: the app suppresses its
// own OS notification when it received the event live, so there are no doubles.

// ── Freeze recurring custody arrangements into immutable history ─────────────
//
// Recurring arrangements (custody_recurring) are expanded live by the Flutter
// engine for today + future dates.  Once a day has passed we materialise the
// occurrence into a real `custody_requests` row so the historical record is
// fixed and unaffected by later edits or deletion of the arrangement.
//
// Runs daily at 00:05 and back-fills the last 14 days (covers brief downtime).
// Now iterates per-household, reading rotation config from the `households`
// collection instead of global `app_settings`.
cronAdd("freezeRecurring", "5 0 * * *", () => {
    try {
        const dao = $app.dao();

        const DAY = 86400000;
        const parse = (s) => { const p = s.split("-"); return new Date(Date.UTC(+p[0], +p[1] - 1, +p[2])); };
        const fmt = (d) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
        const isoDow = (d) => { const x = d.getUTCDay(); return x === 0 ? 7 : x; };
        const mondayOf = (d) => { const m = new Date(d); m.setUTCDate(d.getUTCDate() - (isoDow(d) - 1)); m.setUTCHours(0, 0, 0, 0); return m; };

        const now = new Date();
        const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
        const custodyColl = dao.findCollectionByNameOrId("custody_requests");

        // ── Process each household independently ────────────────────────────
        let households = [];
        try { households = dao.findRecordsByFilter("households", "id != ''", "", 500, 0); }
        catch (_) { households = []; }

        // Fallback: if no households exist yet (pre-migration), use legacy
        // app_settings path so the cron doesn't silently stop working.
        if (households.length === 0) {
            const setting = (key, fb) => {
                try { return dao.findFirstRecordByData("app_settings", "key", key).get("value"); }
                catch (_) { return fb; }
            };
            households = [{
                _legacy: true,
                id: "__legacy__",
                anchor: setting("rotation_anchor", "2026-05-18"),
                evenName: setting("rotation_parent_even", "Bennet"),
                oddName:  setting("rotation_parent_odd", "Jana"),
            }];
        }

        for (const h of households) {
            let anchorStr, parentEvenName, parentOddName, hId;

            if (h._legacy) {
                anchorStr      = h.anchor;
                parentEvenName = h.evenName;
                parentOddName  = h.oddName;
                hId            = "";
            } else {
                anchorStr = h.get("rotation_anchor") || "2026-05-18";
                hId       = h.id;
                // Resolve rotation parent user ids → display names
                const evenId = h.get("rotation_parent_even") || "";
                const oddId  = h.get("rotation_parent_odd")  || "";
                parentEvenName = "";
                parentOddName  = "";
                try {
                    const members = dao.findRecordsByFilter(
                        "household_members",
                        `household = "${hId}" && role = "parent"`, "", 10, 0);
                    for (const m of members) {
                        if (m.get("user") === evenId) parentEvenName = m.get("display_name");
                        if (m.get("user") === oddId)  parentOddName  = m.get("display_name");
                    }
                } catch (_) {}
                if (!parentEvenName || !parentOddName) continue; // incomplete config
            }

            // Rotation scheme: pattern-based (mirrors Dart RotationScheme.ownerAtDay)
            let rotationPattern = [0,0,0,0,0,0,0, 1,1,1,1,1,1,1]; // default weekly
            if (!h._legacy) {
                try {
                    const schemeType = h.get("rotation_scheme_type") || "weekly";
                    const stored = h.get("rotation_pattern");
                    if (Array.isArray(stored) && stored.length > 0) {
                        rotationPattern = stored;
                    } else {
                        // Use preset patterns for known types
                        const presets = {
                            "weekly":               [0,0,0,0,0,0,0, 1,1,1,1,1,1,1],
                            "2-2-5-5":             [0,0, 1,1, 0,0,0,0,0, 1,1,1,1,1],
                            "2-2-3":               [0,0, 1,1, 0,0,0, 1,1, 0,0, 1,1,1],
                            "alternating_weekends": [0,0,0,0,0,0,0, 0,0,0,0,0,1,1],
                        };
                        rotationPattern = presets[schemeType] || rotationPattern;
                    }
                } catch (_) {}
            }
            // Household mode: shared means no rotation — "Both" own every day
            const householdMode = h._legacy ? "custody" : (h.get("mode") || "custody");
            const isShared = householdMode === "shared";

            const anchorDate = parse(anchorStr);
            const rotationOwner = (d) => {
                if (isShared) return "Both";
                const daysSince = Math.floor((d - anchorDate) / DAY);
                const len = rotationPattern.length;
                const idx = ((daysSince % len) + len) % len;
                return rotationPattern[idx] === 0 ? parentEvenName : parentOddName;
            };

            // Mirror the app engine's baseOwner: weekday rule > rotation.
            // Each entry keeps the rule's optional end_date so a lapsed rule
            // falls back to the rotation (inclusive end date).
            let weekdayRuleMap = {};
            try {
                const filter = hId
                    ? `active = true && household = "${hId}"`
                    : "active = true";
                const wdRules = dao.findRecordsByFilter("custody_weekday_rules", filter, "", 500, 0);
                for (const r of wdRules) {
                    weekdayRuleMap[r.getInt("day_of_week")] = {
                        parent:  r.get("parent"),
                        endDate: r.get("end_date") || "",
                    };
                }
            } catch (_) {}
            const baseOwner = (d) => {
                if (isShared) return "Both";
                const wr = weekdayRuleMap[isoDow(d)];
                if (wr && wr.parent && !(wr.endDate && fmt(d) > wr.endDate)) {
                    return wr.parent;
                }
                return rotationOwner(d);
            };

            // Load absence_periods for this household to apply the custody flip
            // when freezing past recurring occurrences (mirrors Dart _applyAbsence).
            let householdAbsences = [];
            try {
                const filter = hId
                    ? `household = "${hId}"`
                    : "id != ''";
                householdAbsences = dao.findRecordsByFilter("absence_periods", filter, "", 500, 0);
            } catch (_) {}

            // Returns true if [parentName] was absent on date string [dStr].
            const wasAbsent = (parentName, dStr) => {
                return householdAbsences.some((a) => {
                    if (a.get("absent_parent") !== parentName) return false;
                    const s = a.get("start_date");
                    const e = a.get("end_date");
                    return dStr >= s && dStr <= e;
                });
            };

            // Flip scheduled parent to the other rotation parent if they were absent.
            const applyAbsence = (scheduled, dStr) => {
                if (!wasAbsent(scheduled, dStr)) return scheduled;
                return scheduled === parentEvenName ? parentOddName : parentEvenName;
            };

            const userId = (name) => {
                try { return dao.findFirstRecordByData("users", "name", name).id; }
                catch (_) { return ""; }
            };

            // Filter arrangements to this household
            let arrangements = [];
            try {
                const filter = hId
                    ? `active = true && household = "${hId}"`
                    : "active = true";
                arrangements = dao.findRecordsByFilter("custody_recurring", filter, "", 500, 0);
            } catch (_) {}

            for (const a of arrangements) {
                const dow       = a.getInt("day_of_week");
                const toParent  = a.get("to_parent");
                const child     = a.get("child_name") || "All";
                const startDate = a.get("start_date") || "";
                const endDate   = a.get("end_date") || "";

                for (let i = 14; i >= 1; i--) {
                    const d = new Date(today.getTime() - i * DAY);
                    if (isoDow(d) !== dow) continue;
                    const dStr = fmt(d);
                    if (startDate && dStr < startDate) continue;
                    if (endDate && dStr > endDate) continue; // arrangement lapsed

                    // Only fire on weeks where the OTHER parent (after absence flip) owns the day.
                    const rawOwner = baseOwner(d);
                    const owner    = applyAbsence(rawOwner, dStr);
                    if (owner === toParent) continue;

                    // Skip if a real request already covers this date + child.
                    let existing = [];
                    try {
                        existing = dao.findRecordsByFilter("custody_requests", "date = {:d}", "", 500, 0, { d: dStr });
                    } catch (_) { existing = []; }
                    const covered = existing.some((r) => {
                        const c = r.get("child_name");
                        return c === child || c === "All" || child === "All";
                    });
                    if (covered) continue;

                    const fromId = userId(owner);
                    const toId   = userId(toParent);
                    if (!fromId || !toId) continue;

                    const rec = new Record(custodyColl);
                    rec.set("date",              dStr);
                    rec.set("from_parent",       owner);
                    rec.set("to_parent",         toParent);
                    rec.set("child_name",        child);
                    rec.set("pickup_time",       a.get("pickup_time") || "");
                    rec.set("return_time",       a.get("return_time") || "");
                    rec.set("return_time_tbd",   a.getBool("return_time_tbd"));
                    rec.set("status",            "accepted");
                    rec.set("note",              a.get("note") || "");
                    rec.set("created_by",        fromId);
                    rec.set("requested_from",    toId);
                    rec.set("to_parent_collects", a.getBool("to_parent_collects"));
                    rec.set("to_parent_returns",  a.getBool("to_parent_returns"));
                    if (hId) rec.set("household", hId);
                    try { dao.saveRecord(rec); } catch (_) {}
                }
            }
        }
    } catch (err) {
        console.log("freezeRecurring error:", err);
    }
});

// ── Invite redemption ────────────────────────────────────────────────────────
//
// A joiner is not yet a household member, so under the household-scoped access
// rules they can't list/read the invite or create their own membership.
// This route runs with elevated (DAO) privileges: it validates the code,
// adds the membership, marks the invite used, and sets the user's active
// household. Keeps invites un-enumerable and closes the self-join hole.
routerAdd("POST", "/api/coplan/accept-invite", (c) => {
    const info = $apis.requestInfo(c);
    const authRecord = info.authRecord;
    if (!authRecord) throw new ForbiddenError("Authentication required.");

    const data = info.data || {};
    const code = (data.code || "").toString().trim().toUpperCase();
    if (!code) throw new BadRequestError("Missing invite code.");

    const dao = $app.dao();

    let invite;
    try {
        invite = dao.findFirstRecordByFilter(
            "household_invites",
            "invite_code = {:code} && used_by = ''",
            { code: code }
        );
    } catch (_) {
        throw new BadRequestError("Invalid or already-used invite code.");
    }

    const expiresStr = invite.get("expires_at");
    if (expiresStr) {
        const exp = new Date(expiresStr);
        if (!isNaN(exp.getTime()) && Date.now() > exp.getTime()) {
            throw new BadRequestError("This invite code has expired.");
        }
    }

    const householdId = invite.get("household");
    const role        = invite.get("role") || "parent";
    const userId      = authRecord.id;
    const displayName = authRecord.get("name") || "Member";

    // Skip if already a member (idempotent).
    let alreadyMember = false;
    try {
        dao.findFirstRecordByFilter(
            "household_members",
            "household = {:h} && user = {:u}",
            { h: householdId, u: userId }
        );
        alreadyMember = true;
    } catch (_) {}

    if (!alreadyMember) {
        const coll = dao.findCollectionByNameOrId("household_members");
        const m = new Record(coll);
        m.set("household",    householdId);
        m.set("user",         userId);
        m.set("role",         role);
        m.set("display_name", displayName);
        m.set("status",       "active");
        dao.saveRecord(m);
    }

    invite.set("used_by", userId);
    dao.saveRecord(invite);

    const user = dao.findRecordById("users", userId);
    user.set("active_household", householdId);
    dao.saveRecord(user);

    return c.json(200, { success: true, household: householdId });
});

// ── Generate recurring expense splits ────────────────────────────────────────
//
// Runs daily at 00:15.  For each active recurring shared_expense whose
// next_due_date <= today, creates a new expense_split for each existing
// split template (copies user + split_type + split_value), then advances
// next_due_date by the recurrence interval.
cronAdd("generateRecurringSplits", "15 0 * * *", () => {
    try {
        const dao = $app.dao();
        const now = new Date();
        const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

        let expenses = [];
        try {
            expenses = dao.findRecordsByFilter(
                "shared_expenses",
                'is_recurring = true && active = true && next_due_date != "" && next_due_date <= {:today}',
                "", 500, 0, { today: todayStr }
            );
        } catch (_) { expenses = []; }

        const splitsColl = dao.findCollectionByNameOrId("expense_splits");

        for (const exp of expenses) {
            const expId       = exp.id;
            const amount      = exp.getInt("amount");
            const householdId = exp.get("household");
            const dueDay      = exp.getInt("due_day") || 1;
            const recurrence  = exp.get("recurrence") || "monthly";
            const endDateStr  = exp.get("end_date") || "";

            // Check end date — if past, deactivate the expense
            if (endDateStr && endDateStr <= todayStr) {
                exp.set("active", false);
                try { dao.saveRecord(exp); } catch (_) {}
                continue;
            }

            // Find existing splits to use as template (most recent ones)
            let templates = [];
            try {
                templates = dao.findRecordsByFilter(
                    "expense_splits",
                    "expense = {:eid}",
                    "-created", 10, 0, { eid: expId }
                );
            } catch (_) { templates = []; }

            // Deduplicate by user — only the latest split per user
            const seen = {};
            const uniqueTemplates = [];
            for (const t of templates) {
                const uid = t.get("user");
                if (!seen[uid]) {
                    seen[uid] = true;
                    uniqueTemplates.push(t);
                }
            }

            // Create new splits
            const nextDueDate = exp.get("next_due_date");
            for (const tmpl of uniqueTemplates) {
                const splitType  = tmpl.get("split_type") || "percentage";
                const splitValue = tmpl.getFloat("split_value");
                const amountDue  = splitType === "percentage"
                    ? Math.round(amount * splitValue / 100)
                    : Math.round(splitValue);

                const rec = new Record(splitsColl);
                rec.set("expense",    expId);
                rec.set("household",  householdId);
                rec.set("user",       tmpl.get("user"));
                rec.set("split_type", splitType);
                rec.set("split_value", splitValue);
                rec.set("amount_due", amountDue);
                rec.set("status",     "pending");
                rec.set("due_date",   nextDueDate);
                try { dao.saveRecord(rec); } catch (_) {}
            }

            // Advance next_due_date
            const parts = nextDueDate.split("-");
            let y = +parts[0], m = +parts[1] - 1, d = dueDay;
            if (recurrence === "monthly")        m += 1;
            else if (recurrence === "quarterly") m += 3;
            else if (recurrence === "annually")  y += 1;
            // Normalise (JS Date handles month overflow)
            const next = new Date(y, m, d);
            const nextStr = `${next.getFullYear()}-${String(next.getMonth() + 1).padStart(2, "0")}-${String(next.getDate()).padStart(2, "0")}`;
            exp.set("next_due_date", nextStr);
            try { dao.saveRecord(exp); } catch (_) {}
        }
    } catch (err) {
        console.log("generateRecurringSplits error:", err);
    }
});

// ── Push notifications (FCM, server-side) ────────────────────────────────────
//
// True background push. The coplan-push sidecar (loopback, 127.0.0.1:8091) does
// the actual FCM HTTP v1 send because PocketBase's JS engine can't mint the
// RS256 OAuth token Google requires. We just look up the recipients' device
// tokens, POST them to the sidecar, and prune any tokens it reports as dead.
//
// The notification COPY mirrors lib/providers/realtime_provider.dart — keep the
// two in sync (this fires for everyone; the app's SSE path only fires while
// open, and suppresses its own OS notification to avoid duplicates).

const PUSH_URL = "http://127.0.0.1:8091/send";

// Send a push to one or more user ids. Never throws — a push failure must not
// break the record write that triggered it.
function sendPush(dao, userIds, title, body, data) {
    try {
        const secret = $os.getenv("PUSH_SECRET");
        if (!secret) { console.log("sendPush: PUSH_SECRET not set, skipping"); return; }

        const ids = (Array.isArray(userIds) ? userIds : [userIds]).filter(Boolean);
        if (ids.length === 0) return;

        // Collect every device token belonging to the recipients.
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

        // Prune tokens the sidecar reported as permanently invalid.
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

const money = (cents) => `R ${((Number(cents) || 0) / 100).toFixed(2)}`;
const cap = (s) => s ? s.charAt(0).toUpperCase() + s.slice(1) : s;

// ── custody_requests → push ──────────────────────────────────────────────────
// Create: notify the parent being asked (requested_from).
onRecordAfterCreateRequest((e) => {
    try {
        const dao = $app.dao();
        const r = e.record;
        const requestedFrom = r.get("requested_from");
        if (!requestedFrom) return;

        const fromParent = r.get("from_parent") || "";
        const toParent   = r.get("to_parent")   || "";
        const child      = r.get("child_name")  || "the children";
        const date       = r.get("date")        || "an upcoming date";
        const rtEmpty    = !(r.get("return_time") || "");
        const rtTbd      = r.getBool("return_time_tbd");
        const isDayXfer  = rtEmpty && !rtTbd;
        const toCollects = r.get("to_parent_collects") === false ? false : true;
        const childStr   = child === "All" ? "the kids" : child;

        const pickupAction = toCollects
            ? `${toParent} collects ${childStr}`
            : `${fromParent} drops off ${childStr}`;

        sendPush(
            dao, requestedFrom,
            isDayXfer ? "Custody Request" : "Handover Requested",
            `${pickupAction} on ${date}${isDayXfer ? "" : " (return expected)"}`,
            { type: "custody_request", id: r.id }
        );
    } catch (err) { console.log("custody create push error:", err); }
}, "custody_requests");

// Update: notify the requester (created_by) when their request is resolved.
onRecordAfterUpdateRequest((e) => {
    try {
        const dao = $app.dao();
        const r = e.record;
        const createdBy = r.get("created_by");
        if (!createdBy) return;

        const status = r.get("status");
        if (!status || status === "pending") return;

        const child = r.get("child_name") || "the children";
        const date  = r.get("date")       || "an upcoming date";
        const whom  = child === "All" ? "the kids" : child;

        let msg = null;
        if (status === "accepted")  msg = `Your ${whom} request for ${date} was accepted`;
        else if (status === "declined")  msg = `Your ${whom} request for ${date} was declined`;
        else if (status === "completed") msg = `Handover for ${whom} on ${date} marked complete`;
        if (!msg) return;

        sendPush(dao, createdBy, `Request ${cap(status)}`, msg,
            { type: "custody_update", id: r.id });
    } catch (err) { console.log("custody update push error:", err); }
}, "custody_requests");

// ── expense_splits → push ────────────────────────────────────────────────────
// Resolve the parent shared_expense title for nicer copy.
function expenseTitle(dao, expenseId) {
    if (!expenseId) return "a shared expense";
    try { return dao.findRecordById("shared_expenses", expenseId).get("title") || "a shared expense"; }
    catch (_) { return "a shared expense"; }
}

// Create: notify the parent who owes a share.
onRecordAfterCreateRequest((e) => {
    try {
        const dao = $app.dao();
        const r = e.record;
        const splitUser = r.get("user");
        if (!splitUser) return;

        const amountStr = money(r.getInt("amount_due"));
        const title = expenseTitle(dao, r.get("expense"));
        sendPush(dao, splitUser, "New shared expense",
            `${title} — your share is ${amountStr}`,
            { type: "expense_split", id: r.id });
    } catch (err) { console.log("expense create push error:", err); }
}, "expense_splits");

// Update → paid: receipt to the parent whose share was settled.
onRecordAfterUpdateRequest((e) => {
    try {
        const dao = $app.dao();
        const r = e.record;
        if (r.get("status") !== "paid") return;
        const splitUser = r.get("user");
        if (!splitUser) return;

        const amountStr = money(r.getInt("amount_due"));
        const title = expenseTitle(dao, r.get("expense"));
        sendPush(dao, splitUser, "Payment recorded",
            `Your ${amountStr} share of ${title} was marked paid`,
            { type: "expense_paid", id: r.id });
    } catch (err) { console.log("expense paid push error:", err); }
}, "expense_splits");

// ── Self-test endpoint ───────────────────────────────────────────────────────
// POST /api/coplan/test-notification  → pushes a TEST notification to the
// caller's own registered devices. Used to verify the whole chain end-to-end
// (token registration → hook → sidecar → FCM → device) without creating junk
// custody/expense records. Returns how many tokens were targeted + the result.
routerAdd("POST", "/api/coplan/test-notification", (c) => {
    const info = $apis.requestInfo(c);
    const authRecord = info.authRecord;
    if (!authRecord) throw new ForbiddenError("Authentication required.");

    const dao = $app.dao();
    const userId = authRecord.id;

    let tokenCount = 0;
    try { tokenCount = dao.findRecordsByFilter("device_tokens", "user = {:u}", "", 50, 0, { u: userId }).length; }
    catch (_) {}

    if (tokenCount === 0) {
        return c.json(200, {
            success: false,
            tokens: 0,
            message: "No registered devices for this user. Open the app (logged in) at least once to register a push token.",
        });
    }

    sendPush(dao, userId, "CoPlan test ✅",
        "If you can see this, push notifications are working.",
        { type: "test" });

    return c.json(200, { success: true, tokens: tokenCount });
});
