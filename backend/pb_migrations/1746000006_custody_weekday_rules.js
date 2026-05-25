/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    const coll = new Collection({
        name: "custody_weekday_rules",
        type: "base",
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id != ''",
        deleteRule: "@request.auth.id != ''",
        schema: [
            // ISO weekday: 1 = Monday … 7 = Sunday
            { name: "day_of_week",      type: "number", required: true  },
            // "Bennet" or "Jana"
            { name: "assigned_parent",  type: "text",   required: true  },
            // Human-readable explanation shown as an override badge
            { name: "reason",           type: "text",   required: false },
            // Set to false to temporarily suspend this rule without deleting it
            { name: "active",           type: "bool",   required: false },
        ],
    });

    dao.saveCollection(coll);

}, (db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("custody_weekday_rules");
    dao.deleteCollection(coll);
});
