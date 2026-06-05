migrate((db) => {
  const dao = new Dao(db);
  const col = dao.findCollectionByNameOrId('rules_base');
  const field = new SchemaField();
  field.name     = 'handover_from';
  field.type     = 'text';
  field.required = false;
  col.schema.addField(field);
  dao.saveCollection(col);
}, (db) => {
  const dao = new Dao(db);
  const col = dao.findCollectionByNameOrId('rules_base');
  col.schema.removeField('handover_from');
  dao.saveCollection(col);
});
