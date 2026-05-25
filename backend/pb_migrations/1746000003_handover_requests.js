/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    const handoverRequests = new Collection({
        name: "handover_requests",
        type: "base",
        schema: [
            { name: "date",            type: "text", required: true  }, // "YYYY-MM-DD"
            { name: "from_parent",     type: "text", required: true  }, // "Bennet"|"Jana"
            { name: "to_parent",       type: "text", required: true  }, // "Bennet"|"Jana"
            { name: "child_name",      type: "text", required: true  }, // "All"|"Henri"|"Chris"
            { name: "pickup_time",     type: "text", required: true  }, // "HH:MM"
            { name: "return_time",     type: "text", required: false }, // "HH:MM" or empty = TBD
            { name: "return_time_tbd", type: "bool", required: false }, // true when return time unknown
            {
                name: "status", type: "select", required: true,
                options: {
                    values: ["requested", "accepted", "declined", "completed"],
                    maxSelect: 1,
                },
            },
            { name: "note", type: "text", required: false },
            {
                name: "created_by", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
            {
                // The other parent — must accept before the handover is confirmed
                name: "requested_from", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
        ],
        // Each parent only sees handovers they created or were asked about
        listRule:   "@request.auth.id = created_by || @request.auth.id = requested_from",
        viewRule:   "@request.auth.id = created_by || @request.auth.id = requested_from",
        createRule: "@request.auth.id != ''",
        // Recipient can accept/decline; creator can mark completed
        updateRule: "@request.auth.id = requested_from || @request.auth.id = created_by",
        deleteRule: "@request.auth.id = created_by",
    });

    dao.saveCollection(handoverRequests);

}, (db) => {
    const dao = new Dao(db);
    try {
        dao.deleteCollection(dao.findCollectionByNameOrId("handover_requests"));
    } catch (_) {}
});
