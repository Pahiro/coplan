/// <reference path="../pb_data/types.d.ts" />
//
// Adds an `owner` relation to households (the member allowed to manage
// membership — remove parents/helpers). Backfills existing households with the
// even-rotation parent, falling back to the first parent member.
//
// PocketBase v0.22 classic migration API: callback receives the dbx builder
// `db`; DAO access via `new Dao(db)`.

migrate((db) => {
    const dao = new Dao(db);
    const households = dao.findCollectionByNameOrId("households");

    households.schema.addField(new SchemaField({
        name: "owner", type: "relation", required: false,
        options: { collectionId: "_pb_users_auth_", maxSelect: 1 },
    }));
    dao.saveCollection(households);

    // Backfill owner for existing households.
    const recs = dao.findRecordsByFilter("households", "id != ''", "", 500, 0);
    for (const h of recs) {
        let owner = h.get("rotation_parent_even");
        if (!owner) {
            try {
                const members = dao.findRecordsByFilter(
                    "household_members",
                    `household = "${h.id}" && role = "parent"`, "", 1, 0);
                if (members.length > 0) owner = members[0].get("user");
            } catch (_) {}
        }
        if (owner) { h.set("owner", owner); dao.saveRecord(h); }
    }
}, (db) => {
    const dao = new Dao(db);
    const households = dao.findCollectionByNameOrId("households");
    const f = households.schema.getFieldByName("owner");
    if (f) { households.schema.removeField(f.id); dao.saveCollection(households); }
});
