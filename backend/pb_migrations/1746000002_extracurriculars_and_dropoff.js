/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    // ── 1. Extracurricular rules ───────────────────────────────────────────────
    // These are added to rules_base so the resolution engine picks them up
    // automatically for every week.
    const rulesBase = dao.findCollectionByNameOrId("rules_base");

    const extracurriculars = [
        // Chris: Bulletjie rugby — Monday evenings, follows weekly rotation
        { child_name: "Chris", day_of_week: 1, event_time: "17:30",
          activity: "Rugby practice",   location: "Laerskool Menlopark", default_parent: "Bennet" },
        // Henri: Chess club — Thursday, goes directly from school (self-attended),
        // then to aftercare. Shown as informational; pickup is part of Thursday routine.
        { child_name: "Henri", day_of_week: 4, event_time: "13:30",
          activity: "Chess club (self)",  location: "School",           default_parent: "Jana" },
        // Henri & Chris: Swimming — Thursday, fixed Jana day
        { child_name: "All",   day_of_week: 4, event_time: "16:00",
          activity: "Swimming",          location: "Tuks HPC",          default_parent: "Jana" },
    ];

    for (const r of extracurriculars) {
        const rec = new Record(rulesBase);
        rec.set("child_name",     r.child_name);
        rec.set("day_of_week",    r.day_of_week);
        rec.set("event_time",     r.event_time);
        rec.set("activity",       r.activity);
        rec.set("location",       r.location);
        rec.set("default_parent", r.default_parent);
        dao.saveRecord(rec);
    }

    // ── 2. Extend manual_overrides for ad-hoc events ──────────────────────────
    // is_adhoc = true  → brand-new one-off event (activity + location required)
    // is_adhoc = false → parent-reassignment override for an existing rules_base slot
    // original_parent is now optional so ad-hoc records don't need it.
    const overridesColl = dao.findCollectionByNameOrId("manual_overrides");

    overridesColl.schema.addField(new SchemaField({
        name: "is_adhoc",  type: "bool", required: false,
    }));
    overridesColl.schema.addField(new SchemaField({
        name: "activity",  type: "text", required: false,
    }));
    overridesColl.schema.addField(new SchemaField({
        name: "location",  type: "text", required: false,
    }));

    // Make original_parent optional — ad-hoc events have no "original" parent
    const origField = overridesColl.schema.getFieldByName("original_parent");
    if (origField) { origField.required = false; }

    dao.saveCollection(overridesColl);

    // ── 3. Add request_type to pickup_requests ────────────────────────────────
    // "pickup"  — "Please come collect [child] from me on [date]"
    // "dropoff" — "I will bring [child] to you on [date]"
    const requestsColl = dao.findCollectionByNameOrId("pickup_requests");

    requestsColl.schema.addField(new SchemaField({
        name: "request_type",
        type: "select",
        required: false,
        options: { maxSelect: 1, values: ["pickup", "dropoff"] },
    }));

    dao.saveCollection(requestsColl);

}, (db) => {
    // ── Rollback ──────────────────────────────────────────────────────────────
    const dao = new Dao(db);

    // Remove added request_type field
    const requestsColl = dao.findCollectionByNameOrId("pickup_requests");
    const rtField = requestsColl.schema.getFieldByName("request_type");
    if (rtField) requestsColl.schema.removeField(rtField.id);
    dao.saveCollection(requestsColl);

    // Remove added manual_override fields
    const overridesColl = dao.findCollectionByNameOrId("manual_overrides");
    for (const fn of ["is_adhoc", "activity", "location"]) {
        const f = overridesColl.schema.getFieldByName(fn);
        if (f) overridesColl.schema.removeField(f.id);
    }
    dao.saveCollection(overridesColl);

    // Note: seeded rules_base records are not removed in rollback
    // (remove manually via admin UI if needed)
});
