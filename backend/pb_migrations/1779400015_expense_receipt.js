/// <reference path="../pb_data/types.d.ts" />
//
// Adds a receipt file field to shared_expenses so a photo of the receipt can
// be attached to an expense (issue #40).

migrate((db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("shared_expenses");
    const schema = coll.schema;

    schema.addField({
        name: "receipt",
        type: "file",
        required: false,
        options: {
            maxSelect: 1,
            maxSize: 10485760, // 10 MB
            mimeTypes: ["image/jpeg", "image/png", "image/webp", "image/heic"],
            thumbs: ["600x0"],
        },
    });

    coll.schema = schema;
    dao.saveCollection(coll);

}, (db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("shared_expenses");
    const schema = coll.schema;
    schema.removeField("receipt");
    coll.schema = schema;
    dao.saveCollection(coll);
});
