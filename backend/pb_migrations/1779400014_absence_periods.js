/// <reference path="../pb_data/types.d.ts" />
//
// Adds the absence_periods collection.
//
// An absence is a date range during which one parent is unavailable. The
// resolution engine (Dart, Kotlin, JS) automatically flips custody to the
// other parent for every day that falls within an absence belonging to the
// scheduled parent.
//
// Fields:
//   household      – required, links to households (access-control anchor)
//   absent_parent  – display name string (matches manual_overrides convention)
//   start_date     – date (inclusive)
//   end_date       – date (inclusive)
//   reason         – short label shown in the UI ("Hiking trip", etc.)
//   note           – optional longer note
//   created_by     – user id of the parent who created the absence
//
// Access rules mirror other household collections (isMember filter, v0.22).

migrate(
  (db) => {
    const dao = new Dao(db);

    const col = new Collection();
    col.name       = "absence_periods";
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
      Object.assign(new SchemaField(), { name: "absent_parent", type: "text",     required: true  }),
      Object.assign(new SchemaField(), { name: "start_date",    type: "text",     required: true  }),
      Object.assign(new SchemaField(), { name: "end_date",      type: "text",     required: true  }),
      Object.assign(new SchemaField(), { name: "reason",        type: "text",     required: false }),
      Object.assign(new SchemaField(), { name: "note",          type: "text",     required: false }),
      Object.assign(new SchemaField(), {
        name: "created_by", type: "relation", required: false,
        options: { collectionId: dao.findCollectionByNameOrId("users").id, maxSelect: 1 },
      }),
    ]);

    dao.saveCollection(col);
  },
  (db) => {
    const dao = new Dao(db);
    dao.deleteCollection(dao.findCollectionByNameOrId("absence_periods"));
  }
);
