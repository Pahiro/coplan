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
// The day-owner conditional uses the rotation settings seeded in app_settings.
cronAdd("freezeRecurring", "5 0 * * *", () => {
    try {
        const dao = $app.dao();

        const setting = (key, fallback) => {
            try { return dao.findFirstRecordByData("app_settings", "key", key).get("value"); }
            catch (_) { return fallback; }
        };
        const anchorStr  = setting("rotation_anchor", "2026-05-18");
        const parentEven = setting("rotation_parent_even", "Bennet");
        const parentOdd  = setting("rotation_parent_odd", "Jana");

        const DAY = 86400000;
        const parse = (s) => { const p = s.split("-"); return new Date(Date.UTC(+p[0], +p[1] - 1, +p[2])); };
        const fmt = (d) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
        const isoDow = (d) => { const x = d.getUTCDay(); return x === 0 ? 7 : x; };
        const mondayOf = (d) => { const m = new Date(d); m.setUTCDate(d.getUTCDate() - (isoDow(d) - 1)); m.setUTCHours(0, 0, 0, 0); return m; };
        const weekOwner = (d) => {
            const weeks = Math.floor((mondayOf(d) - mondayOf(parse(anchorStr))) / (7 * DAY));
            return (((weeks % 2) + 2) % 2) === 0 ? parentEven : parentOdd;
        };
        const userId = (name) => {
            try { return dao.findFirstRecordByData("users", "name", name).id; }
            catch (_) { return ""; }
        };

        const now = new Date();
        const today = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));

        const arrangements = dao.findRecordsByFilter("custody_recurring", "active = true", "", 500, 0);
        const custodyColl = dao.findCollectionByNameOrId("custody_requests");

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

                // Only fire on weeks where the OTHER parent owns the day.
                const owner = weekOwner(d);
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
                if (!fromId || !toId) continue; // need valid relations for visibility

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
                try { dao.saveRecord(rec); } catch (_) { /* skip individual failures */ }
            }
        }
    } catch (err) {
        console.log("freezeRecurring error:", err);
    }
});
