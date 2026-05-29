/// <reference path="../pb_data/types.d.ts" />
//
// AUTHORITATIVE access-control ruleset for all household collections.
//
// Background: 1779400008_access_control.js was committed but never deployed to
// the production server, so every collection was left wide open
// (@request.auth.id != '') — a cross-household data leak. This migration sets
// the complete, final ruleset directly so the running server is correct
// regardless of which earlier migrations did or didn't apply. It also folds in
// 1779400009's invite hardening and fixes household_members.deleteRule (was
// admin-only, which blocked the owner's "remove member").
//
// PocketBase v0.22 classic API. Membership filters use the household_members
// back-relation:
//   isMember:        "household.household_members_via_household.user ?= @request.auth.id"
//   isMemberDirect:  "household_members_via_household.user ?= @request.auth.id" (households)

migrate((db) => {
    const dao = new Dao(db);
    const isMember = "household.household_members_via_household.user ?= @request.auth.id";
    const isMemberDirect = "household_members_via_household.user ?= @request.auth.id";
    const authed = "@request.auth.id != ''";

    const set = (name, rules) => {
        try {
            const c = dao.findCollectionByNameOrId(name);
            if ("list" in rules)   c.listRule   = rules.list;
            if ("view" in rules)   c.viewRule   = rules.view;
            if ("create" in rules) c.createRule = rules.create;
            if ("update" in rules) c.updateRule = rules.update;
            if ("delete" in rules) c.deleteRule = rules.delete;
            dao.saveCollection(c);
        } catch (e) {
            throw new Error("Failed to set rules for " + name + ": " + e);
        }
    };

    set("households", {
        list: isMemberDirect, view: isMemberDirect,
        create: authed, update: isMemberDirect, delete: null,
    });

    set("household_members", {
        list: isMember, view: isMember,
        create: isMember + " || household.owner = @request.auth.id",
        update: "household.owner = @request.auth.id || user = @request.auth.id",
        delete: "household.owner = @request.auth.id || user = @request.auth.id",
    });

    set("children", {
        list: isMember, view: isMember,
        create: isMember, update: isMember, delete: isMember,
    });

    set("household_invites", {
        list: isMember, view: isMember,
        create: isMember, update: isMember, delete: null,
    });

    for (const name of ["rules_base", "manual_overrides", "custody_recurring", "custody_weekday_rules"]) {
        set(name, {
            list: isMember, view: isMember,
            create: isMember, update: isMember, delete: isMember,
        });
    }

    set("custody_requests", {
        list: isMember, view: isMember,
        create: isMember,
        update: isMember + " && (@request.auth.id = requested_from || @request.auth.id = created_by)",
        delete: isMember + " && @request.auth.id = created_by",
    });

    // app_settings is not household-scoped (child colours + app-update metadata
    // read by all authenticated users). Keep readable by any authed user.
    set("app_settings", {
        list: authed, view: authed, create: authed, update: authed,
    });

}, (db) => {
    // Rollback: restore permissive rules.
    const dao = new Dao(db);
    const open = "@request.auth.id != ''";
    for (const name of [
        "households", "household_members", "children", "household_invites",
        "rules_base", "manual_overrides", "custody_requests",
        "custody_recurring", "custody_weekday_rules",
    ]) {
        try {
            const c = dao.findCollectionByNameOrId(name);
            c.listRule = open; c.viewRule = open;
            c.createRule = open; c.updateRule = open;
            dao.saveCollection(c);
        } catch (_) {}
    }
});
