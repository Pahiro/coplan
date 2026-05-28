/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    const householdsColl = dao.findCollectionByNameOrId("households");

    const children = new Collection({
        name: "children",
        type: "base",
        schema: [
            {
                name: "household", type: "relation", required: true,
                options: { collectionId: householdsColl.id, maxSelect: 1 },
            },
            { name: "name",  type: "text", required: true },
            { name: "color", type: "text", required: false }, // hex e.g. "#E65100"
        ],
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id != ''",
        deleteRule: "@request.auth.id != ''",
    });
    dao.saveCollection(children);
}, (db) => {
    const dao = new Dao(db);
    try { dao.deleteCollection(dao.findCollectionByNameOrId("children")); } catch (_) {}
});
