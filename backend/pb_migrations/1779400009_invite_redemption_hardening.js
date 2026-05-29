/// <reference path="../pb_data/types.d.ts" />
//
// Hardens invite handling now that redemption goes through the server-side
// /api/coplan/accept-invite route (pb_hooks), which runs with elevated
// privileges.
//
//   • household_members.createRule: drop the "@request.data.user = @request.auth.id"
//     clause. That clause let ANY authenticated user add themselves to ANY
//     household if they knew its id (a self-join hole). Membership is now
//     created either by the household owner (bootstrap) or by the invite route
//     (superuser, bypasses rules).
//   • household_invites view/update: tighten to members only. Joiners no longer
//     read or update invites directly — the route does it.

migrate((db) => {
    const dao = new Dao(db);
    const isMember =
        "household.household_members_via_household.user ?= @request.auth.id";

    {
        const c = dao.findCollectionByNameOrId("household_members");
        c.createRule = isMember + " || household.owner = @request.auth.id";
        dao.saveCollection(c);
    }

    {
        const c = dao.findCollectionByNameOrId("household_invites");
        c.viewRule   = isMember; // was open
        c.updateRule = isMember; // was open
        dao.saveCollection(c);
    }

}, (db) => {
    // Rollback: restore the previous (looser) rules.
    const dao = new Dao(db);
    const isMember =
        "household.household_members_via_household.user ?= @request.auth.id";

    {
        const c = dao.findCollectionByNameOrId("household_members");
        c.createRule = isMember +
            " || household.owner = @request.auth.id" +
            " || @request.data.user = @request.auth.id";
        dao.saveCollection(c);
    }

    {
        const c = dao.findCollectionByNameOrId("household_invites");
        c.viewRule   = "@request.auth.id != ''";
        c.updateRule = "@request.auth.id != ''";
        dao.saveCollection(c);
    }
});
