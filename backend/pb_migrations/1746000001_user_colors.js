/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    // ── Add preferred_color to the built-in users collection ─────────────────
    const users = dao.findCollectionByNameOrId("users");
    users.schema.addField(new SchemaField({
        name: "preferred_color",
        type: "text",
        required: false,
        options: { max: 7 }, // "#RRGGBB"
    }));
    dao.saveCollection(users);

    // ── app_settings: key-value store for child colours and future config ─────
    const appSettings = new Collection({
        name: "app_settings",
        type: "base",
        schema: [
            { name: "key",   type: "text", required: true  },
            { name: "value", type: "text", required: true  },
            { name: "label", type: "text", required: false }, // human-readable description
        ],
        listRule:   "@request.auth.id != ''",
        viewRule:   "@request.auth.id != ''",
        createRule: "@request.auth.id != ''",
        updateRule: "@request.auth.id != ''",
        deleteRule: "@request.auth.id != ''",
    });
    dao.saveCollection(appSettings);

    // Seed default child colours
    const col = dao.findCollectionByNameOrId("app_settings");
    const seeds = [
        { key: "color_henri", value: "#E65100", label: "Henri's colour" }, // deep orange
        { key: "color_chris", value: "#00695C", label: "Chris's colour"  }, // teal
    ];
    for (const s of seeds) {
        dao.saveRecord(new Record(col, s));
    }

}, (db) => {
    const dao = new Dao(db);
    // Remove the field we added to users
    try {
        const users = dao.findCollectionByNameOrId("users");
        users.schema.removeField("preferred_color");
        dao.saveCollection(users);
    } catch (_) {}
    // Drop app_settings
    try {
        dao.deleteCollection(dao.findCollectionByNameOrId("app_settings"));
    } catch (_) {}
});
