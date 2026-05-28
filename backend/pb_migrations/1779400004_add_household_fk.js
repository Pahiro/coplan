/// <reference path="../pb_data/types.d.ts" />
//
// Adds a `household` relation field to existing data collections so all records
// can be scoped to a household.  Also adds `active_household` to the users
// auth collection.
//
// This migration only adds the schema fields — it does NOT populate them.
// The seed migration (1779400006) handles backfilling for existing data.
//
migrate((db) => {
    const dao = new Dao(db);
    const householdsColl = dao.findCollectionByNameOrId("households");
    const hId = householdsColl.id;

    const householdField = {
        name: "household", type: "relation", required: false,
        options: { collectionId: hId, maxSelect: 1 },
    };

    // Collections that need a household FK
    const names = [
        "rules_base",
        "manual_overrides",
        "custody_requests",
        "custody_recurring",
        "custody_weekday_rules",
    ];

    for (const name of names) {
        try {
            const coll = dao.findCollectionByNameOrId(name);
            coll.schema.addField(new SchemaField(householdField));
            dao.saveCollection(coll);
        } catch (_) {
            // Collection may not exist (e.g. custody_weekday_rules not migrated yet)
        }
    }

    // Add active_household to users auth collection
    const users = dao.findCollectionByNameOrId("users");
    users.schema.addField(new SchemaField({
        name: "active_household", type: "relation", required: false,
        options: { collectionId: hId, maxSelect: 1 },
    }));
    dao.saveCollection(users);

}, (db) => {
    const dao = new Dao(db);

    const names = [
        "rules_base",
        "manual_overrides",
        "custody_requests",
        "custody_recurring",
        "custody_weekday_rules",
    ];
    for (const name of names) {
        try {
            const coll = dao.findCollectionByNameOrId(name);
            const field = coll.schema.getFieldByName("household");
            if (field) { coll.schema.removeField(field.id); dao.saveCollection(coll); }
        } catch (_) {}
    }
    try {
        const users = dao.findCollectionByNameOrId("users");
        const field = users.schema.getFieldByName("active_household");
        if (field) { users.schema.removeField(field.id); dao.saveCollection(users); }
    } catch (_) {}
});
