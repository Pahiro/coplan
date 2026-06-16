/// <reference path="../pb_data/types.d.ts" />
//
// Drops the payment_details collection.
//
// The per-user banking profile was the wrong model: payments don't go to a
// standing household member but to third-party beneficiaries (extra-curricular,
// holiday care, etc.), so payee info belongs on the expense, not the user.
// Split-level payment_reference / payment_note on expense_splits are unaffected.

migrate(
  (db) => {
    const dao = new Dao(db);
    // Guarded for migration drift: the collection may already be absent on a
    // box where it was never created.
    try {
      const col = dao.findCollectionByNameOrId("payment_details");
      dao.deleteCollection(col);
    } catch (_) {
      // already gone — nothing to do
    }
  },
  (db) => {
    // Down: recreate the collection exactly as 1779400022 created it.
    const dao = new Dao(db);

    const col = new Collection();
    col.name       = "payment_details";
    col.type       = "base";
    col.listRule   = "household.household_members_via_household.user ?= @request.auth.id";
    col.viewRule   = "household.household_members_via_household.user ?= @request.auth.id";
    col.createRule = "household.household_members_via_household.user ?= @request.auth.id";
    col.updateRule = "household.household_members_via_household.user ?= @request.auth.id && @request.auth.id = user";
    col.deleteRule = "household.household_members_via_household.user ?= @request.auth.id && @request.auth.id = user";

    col.schema = new Schema([
      Object.assign(new SchemaField(), {
        name: "household", type: "relation", required: true,
        options: { collectionId: dao.findCollectionByNameOrId("households").id, maxSelect: 1 },
      }),
      Object.assign(new SchemaField(), {
        name: "user", type: "relation", required: true,
        options: { collectionId: dao.findCollectionByNameOrId("users").id, maxSelect: 1 },
      }),
      Object.assign(new SchemaField(), { name: "bank_name",         type: "text", required: false }),
      Object.assign(new SchemaField(), { name: "account_holder",    type: "text", required: false }),
      Object.assign(new SchemaField(), { name: "account_number",    type: "text", required: false }),
      Object.assign(new SchemaField(), { name: "branch_code",       type: "text", required: false }),
      Object.assign(new SchemaField(), { name: "payment_link",      type: "url",  required: false }),
      Object.assign(new SchemaField(), { name: "payment_reference", type: "text", required: false }),
      Object.assign(new SchemaField(), { name: "notes",             type: "text", required: false }),
    ]);

    dao.saveCollection(col);
  }
);
