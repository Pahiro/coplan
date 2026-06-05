/// <reference path="../pb_data/types.d.ts" />
//
// Adds the holiday_blocks collection.
//
// A holiday block is a date range where a named parent has custody,
// overriding the normal rotation. Multiple blocks with the same name
// form a holiday period (e.g. "Easter 2026" split between two parents).
//
// Fields:
//   household       – required, links to households (access-control anchor)
//   name            – short label, e.g. "Easter 2026", "June holidays"
//   assigned_parent – display name of the parent who has the kids
//   start_date      – date (inclusive, "yyyy-MM-dd")
//   end_date        – date (inclusive, "yyyy-MM-dd")
//   notes           – optional longer note
//   created_by      – user id of the parent who created the block
//
// Access rules mirror other household collections (isMember filter, v0.22).

migrate(
  (db) => {
    const dao = new Dao(db);

    const col = new Collection();
    col.name       = "holiday_blocks";
    col.type       = "base";
    col.listRule   = "household.household_members_via_household.user ?= @request.auth.id";
    col.viewRule   = "household.household_members_via_household.user ?= @request.auth.id";
    col.createRule = "household.household_members_via_household.user ?= @request.auth.id";
    col.updateRule = "household.household_members_via_household.user ?= @request.auth.id";
    col.deleteRule = "household.household_members_via_household.user ?= @request.auth.id";

    col.schema = new Schema([
      Object.assign(new SchemaField(), {
        name: "household", type: "relation", required: true,
        options: { collectionId: dao.findCollectionByNameOrId("households").id, maxSelect: 1 },
      }),
      Object.assign(new SchemaField(), { name: "name",            type: "text", required: true  }),
      Object.assign(new SchemaField(), { name: "assigned_parent", type: "text", required: true  }),
      Object.assign(new SchemaField(), { name: "start_date",      type: "text", required: true  }),
      Object.assign(new SchemaField(), { name: "end_date",        type: "text", required: true  }),
      Object.assign(new SchemaField(), { name: "notes",           type: "text", required: false }),
      Object.assign(new SchemaField(), {
        name: "created_by", type: "relation", required: false,
        options: { collectionId: dao.findCollectionByNameOrId("users").id, maxSelect: 1 },
      }),
    ]);

    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    const col = dao.findCollectionByNameOrId("holiday_blocks");
    dao.deleteCollection(col);
  }
);
