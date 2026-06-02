migrate(
  (db) => {
    const dao = new Dao(db);
    const col = dao.findCollectionByNameOrId("users");
    const field = new SchemaField();
    field.name = "client_version";
    field.type = "text";
    field.required = false;
    col.schema.addField(field);
    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    const col = dao.findCollectionByNameOrId("users");
    col.schema.removeField(col.schema.getFieldByName("client_version").id);
    dao.saveCollection(col);
  }
);
