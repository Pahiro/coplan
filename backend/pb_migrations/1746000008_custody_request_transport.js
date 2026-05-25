/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao  = new Dao(db);
    const coll = dao.findCollectionByNameOrId("custody_requests");

    // true  = to_parent goes to collect the kids (or from school/event).
    // false = from_parent drops the kids off at to_parent's location.
    coll.schema.addField(new SchemaField({
        name: "to_parent_collects", type: "bool", required: false,
    }));

    // For window requests only.
    // true  = to_parent drives the kids back to from_parent at return time.
    // false = from_parent comes to collect the kids from to_parent.
    coll.schema.addField(new SchemaField({
        name: "to_parent_returns", type: "bool", required: false,
    }));

    dao.saveCollection(coll);

}, (db) => {
    const dao  = new Dao(db);
    const coll = dao.findCollectionByNameOrId("custody_requests");

    const f1 = coll.schema.getFieldByName("to_parent_collects");
    if (f1) coll.schema.removeField(f1.id);

    const f2 = coll.schema.getFieldByName("to_parent_returns");
    if (f2) coll.schema.removeField(f2.id);

    dao.saveCollection(coll);
});
