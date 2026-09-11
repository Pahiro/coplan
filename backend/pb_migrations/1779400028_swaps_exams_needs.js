/// <reference path="../pb_data/types.d.ts" />
//
// Schema for three features:
//
//   • custody_requests.swap_group — day swaps. A swap is two linked day
//     transfers (you take their day, they take yours) sharing one group id;
//     they are accepted, declined and cancelled together.
//   • manual_overrides.kind — "exam" marks a one-off event as a school exam
//     (empty = ordinary event). Display-only; custody resolution ignores it.
//   • needs — the shared "to buy" list. Any member adds an item, one parent
//     claims it ("I'll get it"), marks it bought, and can link the expense.
//
// Classic v0.22 Dao API.

const MEMBER = "household.household_members_via_household.user ?= @request.auth.id";

function addTextField(dao, collectionName, fieldName) {
  const col = dao.findCollectionByNameOrId(collectionName);
  if (col.schema.getFieldByName(fieldName)) return;
  const field = new SchemaField();
  field.name = fieldName;
  field.type = "text";
  field.required = false;
  col.schema.addField(field);
  dao.saveCollection(col);
}

function removeField(dao, collectionName, fieldName) {
  const col = dao.findCollectionByNameOrId(collectionName);
  const field = col.schema.getFieldByName(fieldName);
  if (!field) return;
  col.schema.removeField(field.id);
  dao.saveCollection(col);
}

migrate(
  (db) => {
    const dao = new Dao(db);

    addTextField(dao, "custody_requests", "swap_group");
    addTextField(dao, "manual_overrides", "kind");

    const users      = dao.findCollectionByNameOrId("users").id;
    const households = dao.findCollectionByNameOrId("households").id;
    const expenses   = dao.findCollectionByNameOrId("shared_expenses").id;

    const rel = (name, collectionId, required) => Object.assign(new SchemaField(), {
      name, type: "relation", required,
      options: { collectionId, maxSelect: 1, cascadeDelete: false },
    });
    const text = (name, required) =>
      Object.assign(new SchemaField(), { name, type: "text", required });

    const col = new Collection();
    col.name = "needs";
    col.type = "base";
    col.listRule   = MEMBER;
    col.viewRule   = MEMBER;
    col.createRule = MEMBER + " && @request.data.created_by = @request.auth.id";
    col.updateRule = MEMBER + " && @request.data.household:isset = false" +
      " && @request.data.created_by:isset = false";
    col.deleteRule = MEMBER;
    col.schema = new Schema([
      rel("household", households, true),
      text("title", true),
      text("child_name", false),
      text("note", false),
      text("needed_by", false),
      Object.assign(new SchemaField(), {
        name: "status", type: "select", required: false,
        options: { maxSelect: 1, values: ["open", "claimed", "bought"] },
      }),
      rel("claimed_by", users, false),
      rel("bought_by", users, false),
      text("bought_at", false),
      rel("expense", expenses, false),
      rel("created_by", users, true),
    ]);
    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    try {
      dao.deleteCollection(dao.findCollectionByNameOrId("needs"));
    } catch (_) {}
    removeField(dao, "manual_overrides", "kind");
    removeField(dao, "custody_requests", "swap_group");
  }
);
