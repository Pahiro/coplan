/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    const householdsColl = dao.findCollectionByNameOrId("households");

    const invites = new Collection({
        name: "household_invites",
        type: "base",
        schema: [
            {
                name: "household", type: "relation", required: true,
                options: { collectionId: householdsColl.id, maxSelect: 1 },
            },
            { name: "invite_code", type: "text", required: true },
            { name: "role",        type: "text", required: true }, // "parent" | "helper"
            {
                name: "created_by", type: "relation", required: true,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
            {
                name: "used_by", type: "relation", required: false,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
            { name: "expires_at", type: "date", required: true },
        ],
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id != ''",
        deleteRule: "@request.auth.id != ''",
    });
    dao.saveCollection(invites);
}, (db) => {
    const dao = new Dao(db);
    try { dao.deleteCollection(dao.findCollectionByNameOrId("household_invites")); } catch (_) {}
});
