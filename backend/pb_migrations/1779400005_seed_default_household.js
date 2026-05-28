/// <reference path="../pb_data/types.d.ts" />
//
// Backfill migration: creates a default household from the existing two-user
// setup (Bennet + Jana, children Henri + Chris) and assigns all existing
// records to it.  Reads rotation config from app_settings.
//
migrate((db) => {
    const dao = new Dao(db);

    // ── Find existing users ──────────────────────────────────────────────────
    let bennet, jana;
    try { bennet = dao.findFirstRecordByData("users", "name", "Bennet"); } catch (_) {}
    try { jana   = dao.findFirstRecordByData("users", "name", "Jana");   } catch (_) {}
    if (!bennet && !jana) return; // nothing to seed

    // ── Read rotation config from app_settings ───────────────────────────────
    const setting = (key, fallback) => {
        try { return dao.findFirstRecordByData("app_settings", "key", key).get("value"); }
        catch (_) { return fallback; }
    };
    const anchor    = setting("rotation_anchor", "2026-05-18");
    const evenParent = setting("rotation_parent_even", "Bennet");
    const oddParent  = setting("rotation_parent_odd", "Jana");

    // ── Create household ─────────────────────────────────────────────────────
    const householdsColl = dao.findCollectionByNameOrId("households");
    const household = new Record(householdsColl);
    household.set("name", "Family");
    household.set("rotation_anchor", anchor);
    household.set("mode", "custody");
    // Set rotation parent relations
    if (evenParent === "Bennet" && bennet) {
        household.set("rotation_parent_even", bennet.id);
        household.set("rotation_parent_odd",  jana ? jana.id : "");
    } else {
        household.set("rotation_parent_even", jana ? jana.id : "");
        household.set("rotation_parent_odd",  bennet ? bennet.id : "");
    }
    dao.saveRecord(household);
    const hId = household.id;

    // ── Create household members ─────────────────────────────────────────────
    const membersColl = dao.findCollectionByNameOrId("household_members");
    for (const [user, name] of [[bennet, "Bennet"], [jana, "Jana"]]) {
        if (!user) continue;
        const m = new Record(membersColl);
        m.set("household",    hId);
        m.set("user",         user.id);
        m.set("role",         "parent");
        m.set("display_name", name);
        m.set("status",       "active");
        dao.saveRecord(m);
    }

    // ── Create children ──────────────────────────────────────────────────────
    const childrenColl = dao.findCollectionByNameOrId("children");
    const childData = [
        { name: "Henri", color: setting("color_henri", "#E65100") },
        { name: "Chris", color: setting("color_chris", "#00695C") },
    ];
    for (const c of childData) {
        const rec = new Record(childrenColl);
        rec.set("household", hId);
        rec.set("name",  c.name);
        rec.set("color", c.color);
        dao.saveRecord(rec);
    }

    // ── Set active_household on both users ────────────────────────────────────
    for (const user of [bennet, jana]) {
        if (!user) continue;
        user.set("active_household", hId);
        dao.saveRecord(user);
    }

    // ── Backfill household FK on existing data collections ───────────────────
    const collections = [
        "rules_base",
        "manual_overrides",
        "custody_requests",
        "custody_recurring",
        "custody_weekday_rules",
    ];
    for (const name of collections) {
        try {
            const records = dao.findRecordsByFilter(name, "household = ''", "", 0, 0);
            for (const r of records) {
                r.set("household", hId);
                dao.saveRecord(r);
            }
        } catch (_) {}
    }

}, (db) => {
    // Down: remove seeded data. Household + members + children cascade via
    // PocketBase relation cleanup, but we explicitly clear the FK backfill.
    const dao = new Dao(db);
    const collections = [
        "rules_base", "manual_overrides", "custody_requests",
        "custody_recurring", "custody_weekday_rules",
    ];
    for (const name of collections) {
        try {
            const records = dao.findRecordsByFilter(name, "household != ''", "", 0, 0);
            for (const r of records) { r.set("household", ""); dao.saveRecord(r); }
        } catch (_) {}
    }
    // Clear active_household on users
    try {
        const users = dao.findRecordsByFilter("users", "active_household != ''", "", 0, 0);
        for (const u of users) { u.set("active_household", ""); dao.saveRecord(u); }
    } catch (_) {}
    // Delete seeded household (cascades members/children)
    try {
        const h = dao.findRecordsByFilter("households", "", "", 1, 0);
        if (h.length > 0) dao.deleteRecord(h[0]);
    } catch (_) {}
});
