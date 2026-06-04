// Add is_logistics boolean to rules_base.
// Logistics events (school pickup, regular handover) are greyed out in the UI
// when custody has changed for that day, so they don't clutter the view.
migrate(
  (db) => {
    const dao = new Dao(db);
    const col = dao.findCollectionByNameOrId("rules_base");
    const field = new SchemaField();
    field.name = "is_logistics";
    field.type = "bool";
    field.required = false;
    col.schema.addField(field);
    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    const col = dao.findCollectionByNameOrId("rules_base");
    col.schema.removeField("is_logistics");
    dao.saveCollection(col);
  }
);
