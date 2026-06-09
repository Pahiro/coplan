/// <reference path="../pb_data/types.d.ts" />
//
// Adds the payment_details collection.
//
// Each parent can store their banking details or payment link so other
// household members know where to send money.  Visible to all household
// members but only editable by the owning user.

migrate(
  (db) => {
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
  },
  (db) => {
    const dao = new Dao(db);
    dao.deleteCollection(dao.findCollectionByNameOrId("payment_details"));
  }
);
