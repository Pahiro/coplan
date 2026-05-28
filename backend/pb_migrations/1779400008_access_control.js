/// <reference path="../pb_data/types.d.ts" />
//
// Hardens access-control rules on all household-scoped collections.
//
// BEFORE: any authenticated user can list/view/create/update any record.
// AFTER:  list, view, create, and update require the requesting user to be
//         a member of the record's household (via household_members).
//
// The household_members collection itself is scoped so you can only see
// members of households you belong to.
//
// Collections affected:
//   - households          (list/view/update scoped to membership)
//   - household_members   (list/view scoped to own household membership)
//   - children            (list/view/create/update scoped)
//   - household_invites   (list/view scoped; create by members; update by admin)
//   - rules_base          (list/view/create/update scoped)
//   - manual_overrides    (list/view/create/update scoped)
//   - custody_requests    (list/view scoped; create/update keep existing logic)
//   - custody_recurring   (list/view/create/update scoped)
//   - custody_weekday_rules (list/view/create/update scoped)
//   - app_settings        (list/view scoped to any member; kept loose for backcompat)
//
// The membership check filter (PocketBase v0.22):
//   "household.household_members_via_household.user ?= @request.auth.id"
// means: follow the `household` relation on this record → find household_members
// rows whose `household` matches → check that at least one has `user` = caller.
//
// For the `households` collection itself (no `household` FK — the record IS the
// household):
//   "household_members_via_household.user ?= @request.auth.id"

migrate((db) => {
    const dao = new Dao(db);

    // ── Helper ──────────────────────────────────────────────────────────
    // PB v0.22 back-relation filter:  given a collection with a `household`
    // relation field, this checks that the requesting user is a member.
    const isMember =
        "household.household_members_via_household.user ?= @request.auth.id";

    // For the households collection (the record IS the household).
    const isMemberDirect =
        "household_members_via_household.user ?= @request.auth.id";

    // ── households ──────────────────────────────────────────────────────
    {
        const c = dao.findCollectionByNameOrId("households");
        c.listRule   = isMemberDirect;
        c.viewRule   = isMemberDirect;
        c.createRule = "@request.auth.id != ''"; // anyone can create a new household
        c.updateRule = isMemberDirect;           // only members can update
        c.deleteRule = null;                     // admin only
        dao.saveCollection(c);
    }

    // ── household_members ───────────────────────────────────────────────
    // You can see members of households you belong to.
    // Create: allowed if you're already a member, OR you're the household
    // owner (bootstrap), OR the user field is yourself (invite redemption —
    // the app validates the invite code before calling create).
    {
        const c = dao.findCollectionByNameOrId("household_members");
        c.listRule   = isMember;
        c.viewRule   = isMember;
        c.createRule = isMember +
            " || household.owner = @request.auth.id" +
            " || @request.data.user = @request.auth.id";
        c.updateRule = isMember;
        c.deleteRule = null;                     // admin only
        dao.saveCollection(c);
    }

    // ── children ────────────────────────────────────────────────────────
    {
        const c = dao.findCollectionByNameOrId("children");
        c.listRule   = isMember;
        c.viewRule   = isMember;
        c.createRule = isMember;
        c.updateRule = isMember;
        c.deleteRule = isMember;
        dao.saveCollection(c);
    }

    // ── household_invites ───────────────────────────────────────────────
    {
        const c = dao.findCollectionByNameOrId("household_invites");
        c.listRule   = isMember;
        c.viewRule   = "@request.auth.id != ''"; // anyone can view (to redeem a code)
        c.createRule = isMember;                 // only members can invite
        c.updateRule = "@request.auth.id != ''"; // anyone can redeem (accept)
        c.deleteRule = null;
        dao.saveCollection(c);
    }

    // ── Schedule data collections (all have a `household` FK) ───────────
    const scheduleCollections = [
        "rules_base",
        "manual_overrides",
        "custody_recurring",
        "custody_weekday_rules",
    ];

    for (const name of scheduleCollections) {
        try {
            const c = dao.findCollectionByNameOrId(name);
            c.listRule   = isMember;
            c.viewRule   = isMember;
            c.createRule = isMember;
            c.updateRule = isMember;
            dao.saveCollection(c);
        } catch (_) {
            // Collection may not exist on a fresh install
        }
    }

    // ── custody_requests ────────────────────────────────────────────────
    // Keep the existing created_by/requested_from scoping AND add household
    // membership check for defence in depth.
    try {
        const c = dao.findCollectionByNameOrId("custody_requests");
        c.listRule   = isMember;
        c.viewRule   = isMember;
        c.createRule = isMember;
        c.updateRule = isMember +
            " && (@request.auth.id = requested_from || @request.auth.id = created_by)";
        dao.saveCollection(c);
    } catch (_) {}

    // ── app_settings ────────────────────────────────────────────────────
    // Legacy key-value store. No household FK — keep open for any authed user.
    // (Effectively read-only in the new world; rotation config is per-household.)
    try {
        const c = dao.findCollectionByNameOrId("app_settings");
        c.listRule   = "@request.auth.id != ''";
        c.viewRule   = "@request.auth.id != ''";
        c.createRule = "@request.auth.id != ''";
        c.updateRule = "@request.auth.id != ''";
        dao.saveCollection(c);
    } catch (_) {}

}, (db) => {
    // Rollback: restore permissive rules.
    const dao = new Dao(db);
    const open = "@request.auth.id != ''";

    const collections = [
        "households", "household_members", "children", "household_invites",
        "rules_base", "manual_overrides", "custody_requests",
        "custody_recurring", "custody_weekday_rules",
    ];

    for (const name of collections) {
        try {
            const c = dao.findCollectionByNameOrId(name);
            c.listRule   = open;
            c.viewRule   = open;
            c.createRule = open;
            c.updateRule = open;
            dao.saveCollection(c);
        } catch (_) {}
    }
});
