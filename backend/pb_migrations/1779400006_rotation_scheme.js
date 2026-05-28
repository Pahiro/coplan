/// <reference path="../pb_data/types.d.ts" />

migrate((app) => {
    const dao = app.dao();
    const collection = dao.findCollectionByNameOrId("households");

    // Add rotation_scheme_type field (text, default "weekly")
    collection.schema.addField(new SchemaField({
        name:     "rotation_scheme_type",
        type:     "text",
        required: false,
        options:  { maxSize: 50 },
    }));

    // Add rotation_pattern field (json — stores the day pattern array)
    collection.schema.addField(new SchemaField({
        name:     "rotation_pattern",
        type:     "json",
        required: false,
        options:  { maxSize: 2000 },
    }));

    dao.saveCollection(collection);

    // Default all existing households to "weekly"
    const records = dao.findRecordsByFilter("households", "", "", 500, 0);
    for (const r of records) {
        r.set("rotation_scheme_type", "weekly");
        r.set("rotation_pattern", [0,0,0,0,0,0,0, 1,1,1,1,1,1,1]);
        dao.saveRecord(r);
    }
}, (app) => {
    const dao = app.dao();
    const collection = dao.findCollectionByNameOrId("households");
    collection.schema.removeField("rotation_scheme_type");
    collection.schema.removeField("rotation_pattern");
    dao.saveCollection(collection);
});
