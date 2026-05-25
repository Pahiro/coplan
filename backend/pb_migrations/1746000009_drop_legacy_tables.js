/// <reference path="../pb_data/types.d.ts" />

// Removes two collections that are no longer used by the app:
//
//  • handover_requests — superseded in full by custody_requests (migration 7).
//    Never referenced in any client code.
//
//  • pickup_requests   — the original one-sided request flow, also fully
//    superseded by custody_requests. The Android WorkManager notification
//    poller was the last reference; it has been updated to use custody_requests.

migrate((db) => {
    const dao = new Dao(db);

    for (const name of ["handover_requests", "pickup_requests"]) {
        try {
            const coll = dao.findCollectionByNameOrId(name);
            dao.deleteCollection(coll);
        } catch (_) {
            // Collection may not exist on a fresh install — safe to ignore.
        }
    }
}, (db) => {
    // Down migration: recreate both collections in their last known shape so
    // rolling back leaves the schema consistent (data is not restored).
    const dao = new Dao(db);

    const handover = new Collection({
        name: "handover_requests",
        type: "base",
        schema: [
            { name: "date",         type: "text", required: true  },
            { name: "from_parent",  type: "text", required: true  },
            { name: "to_parent",    type: "text", required: true  },
            { name: "child_name",   type: "text", required: true  },
            { name: "pickup_time",  type: "text", required: true  },
            { name: "return_time",  type: "text", required: false },
            { name: "note",         type: "text", required: false },
            { name: "status",       type: "select", required: true,
              options: { maxSelect: 1, values: ["pending","accepted","declined","completed"] } },
            { name: "created_by",   type: "relation", required: true,
              options: { collectionId: "_pb_users_auth_", cascadeDelete: false } },
            { name: "requested_from", type: "relation", required: true,
              options: { collectionId: "_pb_users_auth_", cascadeDelete: false } },
        ],
    });
    dao.saveCollection(handover);

    const pickup = new Collection({
        name: "pickup_requests",
        type: "base",
        schema: [
            { name: "target_date",    type: "text", required: true  },
            { name: "child_name",     type: "text", required: true  },
            { name: "note",           type: "text", required: false },
            { name: "status",         type: "select", required: true,
              options: { maxSelect: 1, values: ["pending","accepted","declined","completed"] } },
            { name: "requested_by",   type: "relation", required: true,
              options: { collectionId: "_pb_users_auth_", cascadeDelete: false } },
            { name: "requested_from", type: "relation", required: true,
              options: { collectionId: "_pb_users_auth_", cascadeDelete: false } },
        ],
    });
    dao.saveCollection(pickup);
});
