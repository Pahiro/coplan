/// <reference path="../pb_data/types.d.ts" />
//
// Adds a preferred_color field to household_members so that member colours are
// readable by all household members (the users collection is self-access only).
// Migrates existing preferred_color values from user records into their
// household_members records.

migrate((db) => {
    const dao = new Dao(db);

    // Add preferred_color field to household_members
    const coll = dao.findCollectionByNameOrId("household_members");
    const schema = coll.schema;
    schema.addField({
        name: "preferred_color",
        type: "text",
        required: false,
    });
    coll.schema = schema;
    dao.saveCollection(coll);

    // Migrate existing colours from user records
    try {
        const members = dao.findRecordsByFilter("household_members", "id != ''", "", 500, 0);
        for (const m of members) {
            const userId = m.get("user");
            if (!userId) continue;
            try {
                const user = dao.findRecordById("users", userId);
                const color = user.get("preferred_color") || "";
                if (color) {
                    m.set("preferred_color", color);
                    dao.saveRecord(m);
                }
            } catch (_) {}
        }
    } catch (_) {}

}, (db) => {
    const dao = new Dao(db);
    const coll = dao.findCollectionByNameOrId("household_members");
    const schema = coll.schema;
    schema.removeField("preferred_color");
    coll.schema = schema;
    dao.saveCollection(coll);
});
