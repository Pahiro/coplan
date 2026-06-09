/// <reference path="../pb_data/types.d.ts" />
//
// Adds the expense_splits collection.
//
// Each split records how much a specific parent owes for a shared expense.
// Tracks payment status (pending → paid / overdue) with settlement details.
//
// Amounts in cents (integer).

migrate(
  (db) => {
    const dao = new Dao(db);

    const col = new Collection();
    col.name       = "expense_splits";
    col.type       = "base";
    col.listRule   = "household.household_members_via_household.user ?= @request.auth.id";
    col.viewRule   = "household.household_members_via_household.user ?= @request.auth.id";
    col.createRule = "household.household_members_via_household.user ?= @request.auth.id";
    col.updateRule = "household.household_members_via_household.user ?= @request.auth.id";
    col.deleteRule = "household.household_members_via_household.user ?= @request.auth.id";

    col.schema = new Schema([
      Object.assign(new SchemaField(), {
        name: "expense", type: "relation", required: true,
        options: { collectionId: dao.findCollectionByNameOrId("shared_expenses").id, maxSelect: 1 },
      }),
      Object.assign(new SchemaField(), {
        name: "household", type: "relation", required: true,
        options: { collectionId: dao.findCollectionByNameOrId("households").id, maxSelect: 1 },
      }),
      Object.assign(new SchemaField(), {
        name: "user", type: "relation", required: true,
        options: { collectionId: dao.findCollectionByNameOrId("users").id, maxSelect: 1 },
      }),
      Object.assign(new SchemaField(), {
        name: "split_type", type: "select", required: true,
        options: { maxSelect: 1, values: ["percentage", "fixed"] },
      }),
      Object.assign(new SchemaField(), { name: "split_value",        type: "number", required: true  }),
      Object.assign(new SchemaField(), { name: "amount_due",         type: "number", required: true  }),
      Object.assign(new SchemaField(), {
        name: "status", type: "select", required: true,
        options: { maxSelect: 1, values: ["pending", "paid", "overdue"] },
      }),
      Object.assign(new SchemaField(), { name: "due_date",           type: "text",   required: false }),
      Object.assign(new SchemaField(), { name: "paid_date",          type: "text",   required: false }),
      Object.assign(new SchemaField(), { name: "payment_reference",  type: "text",   required: false }),
      Object.assign(new SchemaField(), { name: "payment_note",       type: "text",   required: false }),
    ]);

    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    dao.deleteCollection(dao.findCollectionByNameOrId("expense_splits"));
  }
);
