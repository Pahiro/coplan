/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    // ── 1. Create custody_requests collection ─────────────────────────────────
    const custodyRequests = new Collection({
        name: "custody_requests",
        type: "base",
        schema: [
            { name: "date",            type: "text", required: true  }, // "YYYY-MM-DD"
            { name: "from_parent",     type: "text", required: true  }, // "Bennet"|"Jana" (gives up kids)
            { name: "to_parent",       type: "text", required: true  }, // "Bennet"|"Jana" (receives kids)
            { name: "child_name",      type: "text", required: true  }, // "All"|"Henri"|"Chris"
            { name: "pickup_time",     type: "text", required: false }, // "HH:MM"
            { name: "return_time",     type: "text", required: false }, // "HH:MM" — empty = day transfer
            { name: "return_time_tbd", type: "bool", required: false }, // true when return time unknown
            {
                name: "status", type: "select", required: true,
                options: {
                    values: ["pending", "accepted", "declined", "completed"],
                    maxSelect: 1,
                },
            },
            { name: "note", type: "text", required: false },
            {
                name: "created_by", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
            {
                name: "requested_from", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
        ],
        listRule:   "@request.auth.id = created_by || @request.auth.id = requested_from",
        viewRule:   "@request.auth.id = created_by || @request.auth.id = requested_from",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id = requested_from || @request.auth.id = created_by",
        deleteRule: "@request.auth.id = created_by",
    });
    dao.saveCollection(custodyRequests);

    // ── 2. Helper: resolve user name by ID ───────────────────────────────────
    function userName(userId) {
        try {
            const u = dao.findRecordById("users", userId);
            return u.get("name") || "Unknown";
        } catch (_) {
            return "Unknown";
        }
    }

    // ── 3. Migrate handover_requests ─────────────────────────────────────────
    const destColl = dao.findCollectionByNameOrId("custody_requests");
    try {
        const handovers = dao.findRecordsByExpr("handover_requests", null);
        for (const h of handovers) {
            const rec = new Record(destColl);
            rec.set("date",            h.get("date"));
            rec.set("from_parent",     h.get("from_parent"));
            rec.set("to_parent",       h.get("to_parent"));
            rec.set("child_name",      h.get("child_name"));
            rec.set("pickup_time",     h.get("pickup_time") || "");
            rec.set("return_time",     h.get("return_time") || "");
            rec.set("return_time_tbd", h.get("return_time_tbd") || false);
            // "requested" → "pending"
            const oldStatus = h.get("status");
            rec.set("status", oldStatus === "requested" ? "pending" : (oldStatus || "pending"));
            rec.set("note",            h.get("note") || "");
            rec.set("created_by",      h.get("created_by"));
            rec.set("requested_from",  h.get("requested_from"));
            dao.saveRecord(rec);
        }
    } catch (_) {
        // handover_requests may not exist on fresh installs — skip
    }

    // ── 4. Migrate pickup_requests ────────────────────────────────────────────
    try {
        const pickups = dao.findRecordsByExpr("pickup_requests", null);
        for (const p of pickups) {
            const requestedById   = p.get("requested_by");
            const requestedFromId = p.get("requested_from");
            const requestType     = p.get("request_type") || "pickup";

            // pickup  → requested_by wants to collect from requested_from
            //           from=requested_from, to=requested_by
            // dropoff → requested_by will bring kids to requested_from
            //           from=requested_by,   to=requested_from
            let fromParent, toParent;
            if (requestType === "dropoff") {
                fromParent = userName(requestedById);
                toParent   = userName(requestedFromId);
            } else {
                fromParent = userName(requestedFromId);
                toParent   = userName(requestedById);
            }

            const rec = new Record(destColl);
            rec.set("date",            p.get("target_date") || "");
            rec.set("from_parent",     fromParent);
            rec.set("to_parent",       toParent);
            rec.set("child_name",      p.get("child_name") || "All");
            rec.set("pickup_time",     p.get("pickup_time") || "");
            rec.set("return_time",     "");   // pickup requests were always day transfers
            rec.set("return_time_tbd", false);
            rec.set("status",          p.get("status") || "pending");
            rec.set("note",            p.get("note") || "");
            rec.set("created_by",      requestedById);
            rec.set("requested_from",  requestedFromId);
            dao.saveRecord(rec);
        }
    } catch (_) {
        // pickup_requests may not exist on fresh installs — skip
    }

}, (db) => {
    const dao = new Dao(db);
    try {
        dao.deleteCollection(dao.findCollectionByNameOrId("custody_requests"));
    } catch (_) {}
});
