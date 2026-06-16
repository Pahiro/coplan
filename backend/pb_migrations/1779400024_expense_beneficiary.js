/// <reference path="../pb_data/types.d.ts" />
//
// Adds a free-text `beneficiary` field to shared_expenses: who the payment for
// this expense goes to (e.g. a holiday-care provider or extra-curricular
// vendor). Replaces the removed per-user banking profile — payee info now lives
// on the expense, not the user.

migrate((db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("shared_expenses");
    const schema = coll.schema;

    schema.addField({
        name: "beneficiary",
        type: "text",
        required: false,
    });

    coll.schema = schema;
    dao.saveCollection(coll);

}, (db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("shared_expenses");
    const schema = coll.schema;
    schema.removeField("beneficiary");
    coll.schema = schema;
    dao.saveCollection(coll);
});
