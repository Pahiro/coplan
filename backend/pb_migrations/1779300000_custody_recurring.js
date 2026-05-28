/// <reference path="../pb_data/types.d.ts" />

// Introduces logic-based recurring custody arrangements.
//
// A single `custody_recurring` record describes a standing weekly transfer
// (e.g. "every Tuesday Jana hands the kids to Bennet at 17:30").  Unlike the
// old full-day `custody_weekday_rules`, a recurring arrangement:
//   • carries a pickup/return time, so it only changes responsibility from the
//     pickup time onward (events before it stay with the day owner);
//   • is *conditional* — it only fires on weeks where the OTHER parent owns the
//     day, because you can't be handed kids you already have.
//
// The Flutter resolution engine expands an arrangement into a virtual custody
// request for any future date where the conditions hold.  Past occurrences are
// frozen into real `custody_requests` rows by the daily cron in pb_hooks so
// history stays immutable even if the arrangement is later edited or removed.
//
// The rotation anchor + parity parents are seeded into app_settings so the
// server-side freeze cron can compute the day owner without the client's
// build-time ROTATION_ANCHOR.

migrate((db) => {
    const dao = new Dao(db);

    const coll = new Collection({
        name: "custody_recurring",
        type: "base",
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id != ''",
        deleteRule: "@request.auth.id != ''",
        schema: [
            // ISO weekday this arrangement repeats on: 1 = Monday … 7 = Sunday
            { name: "day_of_week",      type: "number", required: true  },
            // Parent who receives the kids at pickup_time ("Bennet" | "Jana").
            // The other parent is implicit (whoever owns the day that week).
            { name: "to_parent",        type: "text",   required: true  },
            { name: "child_name",       type: "text",   required: true  }, // "All"|"Henri"|"Chris"
            { name: "pickup_time",      type: "text",   required: true  }, // "HH:MM"
            { name: "return_time",      type: "text",   required: false }, // "HH:MM" — empty = day transfer
            { name: "return_time_tbd",  type: "bool",   required: false },
            { name: "to_parent_collects", type: "bool", required: false },
            { name: "to_parent_returns",  type: "bool", required: false },
            // Pattern is not applied to dates before this ("YYYY-MM-DD").
            { name: "start_date",       type: "text",   required: true  },
            { name: "note",             type: "text",   required: false },
            { name: "active",           type: "bool",   required: false },
            {
                name: "created_by", type: "relation", required: false,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
        ],
    });
    dao.saveCollection(coll);

    // ── Seed rotation settings for the server-side freeze cron ────────────────
    // Keep these in sync with the client's --dart-define=ROTATION_ANCHOR.
    // Even week parity from the anchor Monday = rotation_parent_even.
    const settings = dao.findCollectionByNameOrId("app_settings");
    const seeds = [
        { key: "rotation_anchor",      value: "2026-05-18", label: "Monday of a known even-parity (Bennet) week" },
        { key: "rotation_parent_even", value: "Bennet",     label: "Parent who owns even-parity weeks" },
        { key: "rotation_parent_odd",  value: "Jana",       label: "Parent who owns odd-parity weeks" },
    ];
    for (const s of seeds) {
        // Avoid duplicates if the migration is ever re-run on a primed DB.
        try {
            dao.findFirstRecordByData("app_settings", "key", s.key);
        } catch (_) {
            dao.saveRecord(new Record(settings, s));
        }
    }

}, (db) => {
    const dao = new Dao(db);
    try {
        dao.deleteCollection(dao.findCollectionByNameOrId("custody_recurring"));
    } catch (_) {}
    for (const key of ["rotation_anchor", "rotation_parent_even", "rotation_parent_odd"]) {
        try {
            const rec = dao.findFirstRecordByData("app_settings", "key", key);
            dao.deleteRecord(rec);
        } catch (_) {}
    }
});
