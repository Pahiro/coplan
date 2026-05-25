/// <reference path="../pb_data/types.d.ts" />
migrate((db) => {
    const dao = new Dao(db);

    // ── 1. rules_base: remove default_parent, add is_shared ──────────────────
    const rulesColl = dao.findCollectionByNameOrId("rules_base");

    // Remove the default_parent field — parent assignment is now determined
    // entirely by the resolution engine (override → fixed weekday → rotation).
    const dpField = rulesColl.schema.getFieldByName("default_parent");
    if (dpField) rulesColl.schema.removeField(dpField.id);

    // is_shared = true marks events that both parents should know about
    // regardless of whose parenting week it is (e.g. rugby fixtures, parties).
    rulesColl.schema.addField(new SchemaField({
        name: "is_shared", type: "bool", required: false,
    }));

    dao.saveCollection(rulesColl);

    // ── 2. manual_overrides: add is_shared ───────────────────────────────────
    const overridesColl = dao.findCollectionByNameOrId("manual_overrides");

    overridesColl.schema.addField(new SchemaField({
        name: "is_shared", type: "bool", required: false,
    }));

    dao.saveCollection(overridesColl);

}, (db) => {
    const dao = new Dao(db);

    // Remove is_shared from manual_overrides
    const overridesColl = dao.findCollectionByNameOrId("manual_overrides");
    const isf1 = overridesColl.schema.getFieldByName("is_shared");
    if (isf1) overridesColl.schema.removeField(isf1.id);
    dao.saveCollection(overridesColl);

    // Remove is_shared and restore default_parent on rules_base
    const rulesColl = dao.findCollectionByNameOrId("rules_base");
    const isf2 = rulesColl.schema.getFieldByName("is_shared");
    if (isf2) rulesColl.schema.removeField(isf2.id);
    rulesColl.schema.addField(new SchemaField({
        name: "default_parent", type: "text", required: false,
    }));
    dao.saveCollection(rulesColl);
});
