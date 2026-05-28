/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    // First, find the households collection id for the relation.
    const householdsColl = dao.findCollectionByNameOrId("households");

    const members = new Collection({
        name: "household_members",
        type: "base",
        schema: [
            {
                name: "household", type: "relation", required: true,
                options: { collectionId: householdsColl.id, maxSelect: 1 },
            },
            {
                name: "user", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
            { name: "role",         type: "text", required: true  }, // "parent" | "helper"
            { name: "display_name", type: "text", required: true  },
            { name: "status",       type: "text", required: false }, // "active" | "invited"
        ],
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id != ''",
        deleteRule: null, // admin only
    });
    dao.saveCollection(members);
}, (db) => {
    const dao = new Dao(db);
    try { dao.deleteCollection(dao.findCollectionByNameOrId("household_members")); } catch (_) {}
});
