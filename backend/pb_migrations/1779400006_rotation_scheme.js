/// <reference path="../pb_data/types.d.ts" />
//
// Adds rotation scheme fields to households (pattern-based custody rotation).
// Written for the PocketBase v0.22 classic migration API: the callback receives
// the dbx builder `db`, and DAO access is via `new Dao(db)` (NOT `app.dao()`).

migrate((db) => {
    const dao = new Dao(db);
    const collection = dao.findCollectionByNameOrId("households");

    // rotation_scheme_type: which preset ("weekly", "2-2-5-5", …) or "custom"
    collection.schema.addField(new SchemaField({
        name:     "rotation_scheme_type",
        type:     "text",
        required: false,
        options:  { max: 50 },
    }));

    // rotation_pattern: the day-pattern array (0 = even parent, 1 = odd parent)
    collection.schema.addField(new SchemaField({
        name:     "rotation_pattern",
        type:     "json",
        required: false,
        options:  { maxSize: 2000 },
    }));

    dao.saveCollection(collection);

    // Default all existing households to weekly 7/7.
    const records = dao.findRecordsByFilter("households", "id != ''", "", 500, 0);
    for (const r of records) {
        r.set("rotation_scheme_type", "weekly");
        r.set("rotation_pattern", [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1]);
        dao.saveRecord(r);
    }
}, (db) => {
    const dao = new Dao(db);
    const collection = dao.findCollectionByNameOrId("households");
    for (const name of ["rotation_scheme_type", "rotation_pattern"]) {
        const field = collection.schema.getFieldByName(name);
        if (field) collection.schema.removeField(field.id);
    }
    dao.saveCollection(collection);
});
