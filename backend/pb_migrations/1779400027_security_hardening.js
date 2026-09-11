/// <reference path="../pb_data/types.d.ts" />
//
// Security hardening from the 2026-09 review. Registration is open, so every
// rule must hold against a stranger with a valid account.
//
//   • app_settings — writes are admin-only (the in-app updater trusts apk_url;
//     deploy.sh writes via sqlite, so it is unaffected).
//   • users — you can only list yourself (listing leaked every account's name
//     and active_household id across households).
//   • households — the creator must stamp themselves as owner; only the owner
//     can change `owner`.
//   • household_members — only the owner adds rows (invite redemption is
//     server-side); nobody can move a row to another household or re-point it
//     at another user; members can edit their own row but not their role.
//   • custody_requests — created as pending by yourself; only the recipient
//     can change status; the creator may edit a request only while pending;
//     party fields are immutable.
//   • shared_expenses / expense_splits — the payer creates, edits and confirms
//     payment of their own expense's splits (settle-up runs server-side).
//   • custody_weekday_rules / custody_recurring — retired with the repeat
//     feature; locked to admin so old clients can't create rows nobody reads.
//
// Classic v0.22 Dao API. The down migration restores the previous rules.

const MEMBER = "household.household_members_via_household.user ?= @request.auth.id";

const UP = {
  app_settings: {
    createRule: null,
    updateRule: null,
    deleteRule: null,
  },
  users: {
    listRule: "id = @request.auth.id",
  },
  households: {
    createRule: "@request.auth.id != '' && @request.data.owner = @request.auth.id",
    updateRule: "household_members_via_household.user ?= @request.auth.id && " +
      "(@request.data.owner:isset = false || owner = @request.auth.id)",
  },
  household_members: {
    createRule: "household.owner = @request.auth.id",
    updateRule: "@request.data.household:isset = false && @request.data.user:isset = false && " +
      "(household.owner = @request.auth.id || " +
      "(user = @request.auth.id && @request.data.role:isset = false))",
  },
  custody_requests: {
    createRule: MEMBER + " && @request.data.created_by = @request.auth.id" +
      " && @request.data.status = \"pending\"",
    updateRule: MEMBER + " && @request.data.household:isset = false" +
      " && @request.data.created_by:isset = false" +
      " && @request.data.requested_from:isset = false" +
      " && status = \"pending\"" +
      " && (@request.auth.id = requested_from" +
      " || (@request.auth.id = created_by && @request.data.status:isset = false))",
    deleteRule: MEMBER + " && @request.auth.id = created_by",
  },
  shared_expenses: {
    createRule: MEMBER + " && @request.data.created_by = @request.auth.id" +
      " && @request.data.paid_by = @request.auth.id",
    updateRule: MEMBER + " && created_by = @request.auth.id",
  },
  expense_splits: {
    createRule: MEMBER + " && expense.paid_by = @request.auth.id",
    updateRule: MEMBER + " && expense.paid_by = @request.auth.id",
    deleteRule: MEMBER + " && expense.paid_by = @request.auth.id",
  },
  custody_weekday_rules: {
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
  },
  custody_recurring: {
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
  },
};

const OPEN = "@request.auth.id != ''";

const DOWN = {
  app_settings: { createRule: OPEN, updateRule: OPEN, deleteRule: OPEN },
  users: { listRule: "@request.auth.id != \"\"" },
  households: {
    createRule: OPEN,
    updateRule: "household_members_via_household.user ?= @request.auth.id",
  },
  household_members: {
    createRule: MEMBER + " || household.owner = @request.auth.id",
    updateRule: "household.owner = @request.auth.id || user = @request.auth.id",
  },
  custody_requests: {
    createRule: MEMBER,
    updateRule: MEMBER + " && (@request.auth.id = requested_from || @request.auth.id = created_by)",
    deleteRule: MEMBER + " && @request.auth.id = created_by",
  },
  shared_expenses: { createRule: MEMBER, updateRule: MEMBER },
  expense_splits: { createRule: MEMBER, updateRule: MEMBER, deleteRule: MEMBER },
  custody_weekday_rules: {
    listRule: MEMBER, viewRule: MEMBER, createRule: MEMBER, updateRule: MEMBER, deleteRule: MEMBER,
  },
  custody_recurring: {
    listRule: MEMBER, viewRule: MEMBER, createRule: MEMBER, updateRule: MEMBER, deleteRule: MEMBER,
  },
};

function apply(db, table) {
  const dao = new Dao(db);
  for (const name of Object.keys(table)) {
    const col = dao.findCollectionByNameOrId(name);
    const rules = table[name];
    for (const key of Object.keys(rules)) col[key] = rules[key];
    dao.saveCollection(col);
  }
}

migrate(
  (db) => apply(db, UP),
  (db) => apply(db, DOWN)
);
