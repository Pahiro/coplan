/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    const households = new Collection({
        name: "households",
        type: "base",
        schema: [
            { name: "name",                 type: "text",   required: true },
            { name: "rotation_anchor",      type: "text",   required: false }, // "YYYY-MM-DD"
            {
                name: "rotation_parent_even", type: "relation", required: false,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
            {
                name: "rotation_parent_odd", type: "relation", required: false,
                options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
            },
            { name: "mode", type: "text", required: false }, // "custody" | "shared"
        ],
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id != ''",
        deleteRule: null, // admin only
    });
    dao.saveCollection(households);
}, (db) => {
    const dao = new Dao(db);
    try { dao.deleteCollection(dao.findCollectionByNameOrId("households")); } catch (_) {}
});
