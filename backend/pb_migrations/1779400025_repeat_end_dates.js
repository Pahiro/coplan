/// <reference path="../pb_data/types.d.ts" />

// Adds an optional `end_date` ("YYYY-MM-DD") to the repeating-item collections
// so a standing event / custody arrangement / weekday custody rule can stop
// repeating after a chosen day (inclusive). Empty = repeats forever.
//
// `shared_expenses` already carries an `end_date` (migration 1779400020 +
// generateRecurringSplits cron), so it is intentionally not touched here.
//
// Classic v0.22 Dao API (this server rejects the v0.23 `app.dao()` form).

const COLLECTIONS = ["rules_base", "custody_recurring", "custody_weekday_rules"];

migrate(
  (db) => {
    const dao = new Dao(db);
    for (const name of COLLECTIONS) {
      const col = dao.findCollectionByNameOrId(name);
      // Skip if a prior partial run already added it.
      if (col.schema.getFieldByName("end_date")) continue;
      const field = new SchemaField();
      field.name = "end_date";
      field.type = "text";
      field.required = false;
      col.schema.addField(field);
      dao.saveCollection(col);
    }
  },
  (db) => {
    const dao = new Dao(db);
    for (const name of COLLECTIONS) {
      const col = dao.findCollectionByNameOrId(name);
      const field = col.schema.getFieldByName("end_date");
      if (field) {
        col.schema.removeField(field.id);
        dao.saveCollection(col);
      }
    }
  }
);
