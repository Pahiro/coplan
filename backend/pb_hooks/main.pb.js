/// <reference path="../pb_data/types.d.ts" />

// Notifications are handled via PocketBase real-time subscriptions in the
// Flutter app (flutter_local_notifications + SSE). No server-side push hooks
// are required.

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
        const today = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
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
            let weekdayRuleMap = {};
            try {
                const filter = hId
                    ? `active = true && household = "${hId}"`
                    : "active = true";
                const wdRules = dao.findRecordsByFilter("custody_weekday_rules", filter, "", 500, 0);
                for (const r of wdRules) {
                    weekdayRuleMap[r.getInt("day_of_week")] = r.get("parent");
                }
            } catch (_) {}
            const baseOwner = (d) => {
                if (isShared) return "Both";
                return weekdayRuleMap[isoDow(d)] || rotationOwner(d);
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

                for (let i = 14; i >= 1; i--) {
                    const d = new Date(today.getTime() - i * DAY);
                    if (isoDow(d) !== dow) continue;
                    const dStr = fmt(d);
                    if (startDate && dStr < startDate) continue;

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
