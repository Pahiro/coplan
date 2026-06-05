migrate((db) => {
  const dao = new Dao(db);
  const col = dao.findCollectionByNameOrId('manual_overrides');
  const field = new SchemaField();
  field.name     = 'is_logistics';
  field.type     = 'bool';
  field.required = false;
  col.schema.addField(field);
  dao.saveCollection(col);
}, (db) => {
  const dao = new Dao(db);
  const col = dao.findCollectionByNameOrId('manual_overrides');
  col.schema.removeField('is_logistics');
  dao.saveCollection(col);
});
