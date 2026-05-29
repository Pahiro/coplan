/// <reference path="../pb_data/types.d.ts" />
//
// Adds note and end_time fields to manual_overrides for one-off events.

migrate((db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("manual_overrides");
    const schema = coll.schema;

    schema.addField({
        name: "note",
        type: "text",
        required: false,
    });
    schema.addField({
        name: "end_time",
        type: "text",
        required: false,
    });

    coll.schema = schema;
    dao.saveCollection(coll);

}, (db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("manual_overrides");
    const schema = coll.schema;
    schema.removeField("note");
    schema.removeField("end_time");
    coll.schema = schema;
    dao.saveCollection(coll);
});
