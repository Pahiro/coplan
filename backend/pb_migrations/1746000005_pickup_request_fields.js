/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("pickup_requests");

    coll.schema.addField(new SchemaField({
        name: "pickup_time", type: "text", required: false,
    }));
    coll.schema.addField(new SchemaField({
        name: "location", type: "text", required: false,
    }));

    dao.saveCollection(coll);
}, (db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("pickup_requests");

    const tf = coll.schema.getFieldByName("pickup_time");
    if (tf) coll.schema.removeField(tf.id);
    const lf = coll.schema.getFieldByName("location");
    if (lf) coll.schema.removeField(lf.id);

    dao.saveCollection(coll);
});
