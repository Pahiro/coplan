/// <reference path="../pb_data/types.d.ts" />
//
// Adds the shared_expenses collection.
//
// An expense is a cost incurred for one or more children that is split
// between household members.  Can be once-off (sign-up fee, shoes) or
// recurring (monthly swimming, aftercare).
//
// Amounts are stored in cents (integer) to avoid floating-point issues.
//
// Access rules mirror other household collections (isMember filter, v0.22).

migrate(
  (db) => {
    const dao = new Dao(db);

    const col = new Collection();
    col.name       = "shared_expenses";
    col.type       = "base";
    col.listRule   = "household.household_members_via_household.user ?= @request.auth.id";
    col.viewRule   = "household.household_members_via_household.user ?= @request.auth.id";
    col.createRule = "household.household_members_via_household.user ?= @request.auth.id";
    col.updateRule = "household.household_members_via_household.user ?= @request.auth.id";
    col.deleteRule = "household.household_members_via_household.user ?= @request.auth.id && @request.auth.id = created_by";

    col.schema = new Schema([
      Object.assign(new SchemaField(), {
        name: "household", type: "relation", required: true,
        options: { collectionId: dao.findCollectionByNameOrId("households").id, maxSelect: 1 },
      }),
      Object.assign(new SchemaField(), { name: "title",       type: "text",   required: true  }),
      Object.assign(new SchemaField(), { name: "description", type: "text",   required: false }),
      Object.assign(new SchemaField(), { name: "child_name",  type: "text",   required: false }),
      Object.assign(new SchemaField(), { name: "amount",      type: "number", required: true  }),
      Object.assign(new SchemaField(), { name: "currency",    type: "text",   required: false }),
      Object.assign(new SchemaField(), {
        name: "category", type: "select", required: false,
        options: { maxSelect: 1, values: ["education", "sport", "medical", "clothing", "other"] },
      }),
      Object.assign(new SchemaField(), { name: "is_recurring",   type: "bool", required: false }),
      Object.assign(new SchemaField(), {
        name: "recurrence", type: "select", required: false,
        options: { maxSelect: 1, values: ["monthly", "quarterly", "annually"] },
      }),
      Object.assign(new SchemaField(), { name: "due_day",        type: "number", required: false }),
      Object.assign(new SchemaField(), { name: "next_due_date",  type: "text",   required: false }),
      Object.assign(new SchemaField(), { name: "start_date",     type: "text",   required: false }),
      Object.assign(new SchemaField(), { name: "end_date",       type: "text",   required: false }),
      Object.assign(new SchemaField(), {
        name: "paid_by", type: "relation", required: false,
        options: { collectionId: dao.findCollectionByNameOrId("users").id, maxSelect: 1 },
      }),
      Object.assign(new SchemaField(), { name: "active",     type: "bool", required: false }),
      Object.assign(new SchemaField(), {
        name: "created_by", type: "relation", required: false,
        options: { collectionId: dao.findCollectionByNameOrId("users").id, maxSelect: 1 },
      }),
    ]);

    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    dao.deleteCollection(dao.findCollectionByNameOrId("shared_expenses"));
  }
);
