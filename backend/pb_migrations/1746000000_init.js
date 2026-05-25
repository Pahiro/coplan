/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    // ── rules_base ────────────────────────────────────────────────────────────
    const rulesBase = new Collection({
        name: "rules_base",
        type: "base",
        schema: [
            { name: "child_name",     type: "text",   required: true  },
            { name: "day_of_week",    type: "number", required: true  }, // 1=Mon…7=Sun
            { name: "event_time",     type: "text",   required: true  }, // "HH:mm"
            { name: "location",       type: "text",   required: true  },
            { name: "activity",       type: "text",   required: true  },
            { name: "default_parent", type: "text",   required: true  }, // "Bennet"|"Jana"
        ],
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id != ''",
        deleteRule: "@request.auth.id != ''",
    });
    dao.saveCollection(rulesBase);

    // ── manual_overrides ──────────────────────────────────────────────────────
    const manualOverrides = new Collection({
        name: "manual_overrides",
        type: "base",
        schema: [
            { name: "target_date",      type: "text",     required: true }, // "YYYY-MM-DD"
            { name: "child_name",       type: "text",     required: true },
            { name: "original_parent",  type: "text",     required: true },
            { name: "assigned_parent",  type: "text",     required: true },
            { name: "override_time",    type: "text",     required: false },
            { name: "reason",           type: "text",     required: true },
            {
                name: "created_by", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 }
            },
        ],
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id = created_by",
        deleteRule: "@request.auth.id = created_by",
    });
    dao.saveCollection(manualOverrides);

    // ── pickup_requests ───────────────────────────────────────────────────────
    const pickupRequests = new Collection({
        name: "pickup_requests",
        type: "base",
        schema: [
            { name: "target_date",    type: "text", required: true }, // "YYYY-MM-DD"
            { name: "child_name",     type: "text", required: true },
            {
                name: "requested_by", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 }
            },
            {
                name: "requested_from", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 }
            },
            { name: "note",   type: "text", required: false },
            {
                name: "status", type: "select", required: true,
                options: { values: ["pending", "accepted", "declined"], maxSelect: 1 }
            },
        ],
        // Each parent only sees requests they sent or received
        listRule:   "@request.auth.id = requested_by || @request.auth.id = requested_from",
        viewRule:   "@request.auth.id = requested_by || @request.auth.id = requested_from",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id = requested_from", // only recipient can accept/decline
        deleteRule: "@request.auth.id = requested_by",
    });
    dao.saveCollection(pickupRequests);

    // ── Seed base schedule rules ──────────────────────────────────────────────
    // After collections are created, seed the standing rules from the spec.
    const col = dao.findCollectionByNameOrId("rules_base");
    const seeds = [
        // Mon–Fri: standard school pickup (rotation determines parent except fixed days)
        { child_name: "All", day_of_week: 1, event_time: "14:30", location: "Crawford College", activity: "School pickup",     default_parent: "Bennet" },
        { child_name: "All", day_of_week: 2, event_time: "14:30", location: "Crawford College", activity: "School pickup",     default_parent: "Bennet" }, // Tue: Bennet (Bible study)
        { child_name: "All", day_of_week: 3, event_time: "14:30", location: "Crawford College", activity: "School pickup",     default_parent: "Jana"   }, // Wed: Jana (climbing)
        { child_name: "All", day_of_week: 4, event_time: "14:30", location: "Crawford College", activity: "School pickup",     default_parent: "Jana"   }, // Thu: Jana
        { child_name: "Henri", day_of_week: 4, event_time: "16:00", location: "Swim Club",      activity: "Swimming practice", default_parent: "Jana"   },
        { child_name: "Chris", day_of_week: 4, event_time: "16:00", location: "Swim Club",      activity: "Swimming practice", default_parent: "Jana"   },
        { child_name: "All", day_of_week: 5, event_time: "14:30", location: "Crawford College", activity: "School pickup",     default_parent: "Bennet" },
        // Sunday: weekly handover at church
        { child_name: "All", day_of_week: 7, event_time: "11:00", location: "Church",           activity: "Weekly handover",   default_parent: "Bennet" },
    ];
    for (const s of seeds) {
        dao.saveRecord(new Record(col, s));
    }

}, (db) => {
    const dao = new Dao(db);
    for (const name of ["pickup_requests", "manual_overrides", "rules_base"]) {
        try { dao.deleteCollection(dao.findCollectionByNameOrId(name)); } catch (_) {}
    }
});
