/// <reference path="../pb_data/types.d.ts" />

// Server logic for CoPlan:
//   • POST /api/coplan/accept-invite      — privileged invite redemption
//   • POST /api/coplan/settle-up          — clears the balance between parents
//   • POST /api/coplan/test-notification  — push self-test
//   • generateRecurringSplits cron        — recurring expense splits + overdue
//   • push hooks                          — FCM via the coplan-push sidecar
//
// ⚠️ PocketBase v0.22 runs each handler in an isolated context: top-level
// declarations in this file are NOT visible inside handlers. Shared helpers
// live in coplan_utils.js and are loaded per handler with require().
//
// Custody resolution lives in the Flutter engine (and its Kotlin mirror for
// widgets); nothing here resolves the schedule.

// ── Invite redemption ────────────────────────────────────────────────────────
//
// A joiner is not yet a household member, so under the household-scoped access
// rules they can't list/read the invite or create their own membership.
// This route runs with elevated (DAO) privileges: it validates the code,
// adds the membership, marks the invite used, and sets the user's active
// household. Keeps invites un-enumerable and closes the self-join hole.
routerAdd("POST", "/api/coplan/accept-invite", (c) => {
    const info = $apis.requestInfo(c);
    const authRecord = info.authRecord;
    if (!authRecord) throw new ForbiddenError("Authentication required.");

    const data = info.data || {};
    const code = (data.code || "").toString().trim().toUpperCase();
    if (!code) throw new BadRequestError("Missing invite code.");

    const dao = $app.dao();

    let invite;
    try {
        invite = dao.findFirstRecordByFilter(
            "household_invites",
            "invite_code = {:code} && used_by = ''",
            { code: code }
        );
    } catch (_) {
        throw new BadRequestError("Invalid or already-used invite code.");
    }

    const expiresStr = invite.get("expires_at");
    if (expiresStr) {
        const exp = new Date(expiresStr);
        if (!isNaN(exp.getTime()) && Date.now() > exp.getTime()) {
            throw new BadRequestError("This invite code has expired.");
        }
    }

    const householdId = invite.get("household");
    const role        = invite.get("role") || "parent";
    const userId      = authRecord.id;
    const displayName = authRecord.get("name") || "Member";

    // Skip if already a member (idempotent).
    let alreadyMember = false;
    try {
        dao.findFirstRecordByFilter(
            "household_members",
            "household = {:h} && user = {:u}",
            { h: householdId, u: userId }
        );
        alreadyMember = true;
    } catch (_) {}

    if (!alreadyMember) {
        const coll = dao.findCollectionByNameOrId("household_members");
        const m = new Record(coll);
        m.set("household",    householdId);
        m.set("user",         userId);
        m.set("role",         role);
        m.set("display_name", displayName);
        m.set("status",       "active");
        dao.saveRecord(m);
    }

    invite.set("used_by", userId);
    dao.saveRecord(invite);

    const user = dao.findRecordById("users", userId);
    user.set("active_household", householdId);
    dao.saveRecord(user);

    return c.json(200, { success: true, household: householdId });
});

// ── Recurring expense splits + overdue marking ───────────────────────────────
//
// Runs daily at 00:15.
//   1. Pending splits past their due date become "overdue" (previously every
//      client did this on each fetch, which the payer-only split rules forbid).
//   2. For each active recurring expense whose next_due_date <= today, creates
//      the split for that due date — unless one already exists (the first
//      split is created with the expense, which used to double-charge the
//      first period) — then advances next_due_date by the recurrence.
cronAdd("generateRecurringSplits", "15 0 * * *", () => {
    const u = require(`${__hooks}/coplan_utils.js`);
    try {
        const dao = $app.dao();
        const todayStr = u.isoLocal(new Date());

        try {
            const late = dao.findRecordsByFilter(
                "expense_splits",
                'status = "pending" && due_date != "" && due_date < {:today}',
                "", 2000, 0, { today: todayStr }
            );
            for (const s of late) {
                s.set("status", "overdue");
                try { dao.saveRecord(s); } catch (_) {}
            }
        } catch (_) {}

        let expenses = [];
        try {
            expenses = dao.findRecordsByFilter(
                "shared_expenses",
                'is_recurring = true && active = true && next_due_date != "" && next_due_date <= {:today}',
                "", 500, 0, { today: todayStr }
            );
        } catch (_) { expenses = []; }

        const splitsColl = dao.findCollectionByNameOrId("expense_splits");

        for (const exp of expenses) {
            const expId       = exp.id;
            const amount      = exp.getInt("amount");
            const householdId = exp.get("household");
            const dueDay      = exp.getInt("due_day") || 1;
            const recurrence  = exp.get("recurrence") || "monthly";
            const endDateStr  = exp.get("end_date") || "";

            // Past its end date → deactivate instead of generating.
            if (endDateStr && endDateStr < todayStr) {
                exp.set("active", false);
                try { dao.saveRecord(exp); } catch (_) {}
                continue;
            }

            // Latest split per user is the template for the next one.
            let templates = [];
            try {
                templates = dao.findRecordsByFilter(
                    "expense_splits", "expense = {:eid}", "-created", 10, 0, { eid: expId }
                );
            } catch (_) { templates = []; }

            const seen = {};
            const uniqueTemplates = [];
            for (const t of templates) {
                const uid = t.get("user");
                if (!seen[uid]) {
                    seen[uid] = true;
                    uniqueTemplates.push(t);
                }
            }

            const nextDueDate = exp.get("next_due_date");
            for (const tmpl of uniqueTemplates) {
                const uid = tmpl.get("user");

                let exists = false;
                try {
                    dao.findFirstRecordByFilter(
                        "expense_splits", "expense = {:e} && user = {:u} && due_date = {:d}",
                        { e: expId, u: uid, d: nextDueDate }
                    );
                    exists = true;
                } catch (_) {}
                if (exists) continue;

                const splitType  = tmpl.get("split_type") || "percentage";
                const splitValue = tmpl.getFloat("split_value");
                const amountDue  = splitType === "percentage"
                    ? Math.round(amount * splitValue / 100)
                    : Math.round(splitValue);

                const rec = new Record(splitsColl);
                rec.set("expense",     expId);
                rec.set("household",   householdId);
                rec.set("user",        uid);
                rec.set("split_type",  splitType);
                rec.set("split_value", splitValue);
                rec.set("amount_due",  amountDue);
                rec.set("status",      "pending");
                rec.set("due_date",    nextDueDate);
                try {
                    dao.saveRecord(rec);
                    u.sendPush(dao, uid, "Shared expense due",
                        `${exp.get("title") || "A shared expense"} — your share is ${u.money(amountDue)}`,
                        { type: "expense_split", id: rec.id });
                } catch (_) {}
            }

            // Advance next_due_date (JS Date normalises month overflow; the
            // app limits due_day to 1–28 so months never skip).
            const parts = nextDueDate.split("-");
            let y = +parts[0], m = +parts[1] - 1;
            if (recurrence === "monthly")        m += 1;
            else if (recurrence === "quarterly") m += 3;
            else if (recurrence === "annually")  y += 1;
            exp.set("next_due_date", u.isoLocal(new Date(y, m, dueDay)));
            try { dao.saveRecord(exp); } catch (_) {}
        }
    } catch (err) {
        console.log("generateRecurringSplits error:", err);
    }
});

// ── Settle up ────────────────────────────────────────────────────────────────
//
// POST /api/coplan/settle-up { household, reference?, note? }
//
// Marks every unpaid split between the caller and the other members of the
// household as paid, in both directions, so one payment of the net clears the
// slate. Only the parent who is owed on balance (net >= 0) may confirm it —
// the parent who owes can't clear their own debt. Runs with DAO privileges
// because the split rules only let a payer update their own expense's splits.
routerAdd("POST", "/api/coplan/settle-up", (c) => {
    const u = require(`${__hooks}/coplan_utils.js`);
    const info = $apis.requestInfo(c);
    const auth = info.authRecord;
    if (!auth) throw new ForbiddenError("Authentication required.");

    const data        = info.data || {};
    const householdId = String(data.household || "");
    const reference   = String(data.reference || "").slice(0, 200);
    const note        = String(data.note || "").slice(0, 500);
    if (!householdId) throw new BadRequestError("Missing household.");

    const dao = $app.dao();
    try {
        dao.findFirstRecordByFilter(
            "household_members", "household = {:h} && user = {:u}",
            { h: householdId, u: auth.id }
        );
    } catch (_) {
        throw new ForbiddenError("You are not a member of this household.");
    }

    let splits = [];
    try {
        splits = dao.findRecordsByFilter(
            "expense_splits", 'household = {:h} && status != "paid"', "", 2000, 0, { h: householdId }
        );
    } catch (_) { splits = []; }

    const payers = {};
    const payerOf = (expenseId) => {
        if (!(expenseId in payers)) {
            try { payers[expenseId] = dao.findRecordById("shared_expenses", expenseId).get("paid_by") || ""; }
            catch (_) { payers[expenseId] = ""; }
        }
        return payers[expenseId];
    };

    let net = 0;
    const involved = [];
    const counterparts = {};
    for (const s of splits) {
        const payer  = payerOf(s.get("expense"));
        const debtor = s.get("user");
        const due    = s.getInt("amount_due");
        if (!payer || payer === debtor) continue;
        if (debtor === auth.id) {
            net -= due;
            involved.push(s);
            counterparts[payer] = true;
        } else if (payer === auth.id) {
            net += due;
            involved.push(s);
            counterparts[debtor] = true;
        }
    }

    if (involved.length === 0) return c.json(200, { count: 0, netCents: 0 });
    if (net < 0) {
        throw new ForbiddenError(
            "You owe on balance, so the parent who is owed confirms the settle-up once they've been paid.");
    }

    const today = u.isoLocal(new Date());
    dao.runInTransaction((txDao) => {
        for (const s of involved) {
            s.set("status",            "paid");
            s.set("paid_date",         today);
            s.set("payment_reference", reference);
            s.set("payment_note",      note);
            txDao.saveRecord(s);
        }
    });

    const who = u.memberName(dao, householdId, auth.id) || "Your co-parent";
    u.sendPush(dao, Object.keys(counterparts), "Settled up",
        net > 0
            ? `${who} confirmed receiving ${u.money(net)} — shared expenses between you are settled`
            : `${who} settled up — shared expenses between you are cleared`,
        { type: "settle_up" });

    return c.json(200, { count: involved.length, netCents: net });
});

// ── custody_requests → push ──────────────────────────────────────────────────

// Create: notify the parent being asked. A swap is two rows; push once, when
// the second leg lands, describing both days.
onRecordAfterCreateRequest((e) => {
    const u = require(`${__hooks}/coplan_utils.js`);
    try {
        const dao = $app.dao();
        const r = e.record;
        const requestedFrom = r.get("requested_from");
        if (!requestedFrom) return;

        const childStr = u.kids(r.get("child_name"));
        const group    = r.get("swap_group") || "";

        if (group) {
            const legs = u.swapLegs(dao, group);
            if (legs.length < 2) return;
            const recipient = u.memberName(dao, r.get("household"), requestedFrom);
            const theirDay  = legs.find((l) => l.get("to_parent") === recipient) || legs[0];
            const askerDay  = legs.find((l) => l.id !== theirDay.id) || legs[1];
            const asker     = theirDay.get("from_parent") || "Your co-parent";
            u.sendPush(dao, requestedFrom, "Swap requested",
                `${asker} asks to swap days: you take ${childStr} on ${u.fmtDay(theirDay.get("date"))}, ` +
                `${asker} takes them on ${u.fmtDay(askerDay.get("date"))}`,
                { type: "custody_request", id: r.id });
            return;
        }

        const fromParent = r.get("from_parent") || "";
        const toParent   = r.get("to_parent")   || "";
        const isWindow   = !!(r.get("return_time") || "") || r.getBool("return_time_tbd");
        const toCollects = r.get("to_parent_collects") === false ? false : true;
        const action = toCollects
            ? `${toParent} collects ${childStr}`
            : `${fromParent} drops off ${childStr}`;

        u.sendPush(dao, requestedFrom,
            isWindow ? "Time window requested" : "Day handover requested",
            `${action} on ${u.fmtDay(r.get("date"))}${isWindow ? " (and brings them back)" : ""}`,
            { type: "custody_request", id: r.id });
    } catch (err) { console.log("custody create push error:", err); }
}, "custody_requests");

// Update: notify the requester when the status actually changes. For a swap,
// push once, after the last leg has moved to the new status.
onRecordAfterUpdateRequest((e) => {
    const u = require(`${__hooks}/coplan_utils.js`);
    try {
        const dao = $app.dao();
        const r = e.record;
        const createdBy = r.get("created_by");
        if (!createdBy) return;

        const status = r.get("status");
        const before = r.originalCopy().get("status");
        if (!status || status === before || status === "pending") return;
        if (status !== "accepted" && status !== "declined") return;

        const whom  = u.kids(r.get("child_name"));
        const group = r.get("swap_group") || "";

        let msg;
        if (group) {
            const legs = u.swapLegs(dao, group);
            if (legs.some((l) => l.get("status") !== status)) return;
            const days = legs.map((l) => u.fmtDay(l.get("date"))).join(" ⇄ ");
            msg = `Your swap for ${whom} (${days}) was ${status}`;
        } else {
            msg = `Your request for ${whom} on ${u.fmtDay(r.get("date"))} was ${status}`;
        }

        u.sendPush(dao, createdBy,
            status === "accepted" ? "Request accepted" : "Request declined",
            msg, { type: "custody_update", id: r.id });
    } catch (err) { console.log("custody update push error:", err); }
}, "custody_requests");

// Delete: the creator withdrew a pending request or cancelled an agreement —
// tell the other parent. For a swap, push once the last leg is gone.
onRecordAfterDeleteRequest((e) => {
    const u = require(`${__hooks}/coplan_utils.js`);
    try {
        const dao = $app.dao();
        const r = e.record;
        const status = r.get("status");
        if (status !== "accepted" && status !== "pending") return;
        const other = r.get("requested_from");
        if (!other) return;

        const group = r.get("swap_group") || "";
        if (group && u.swapLegs(dao, group).length > 0) return;

        const who  = u.memberName(dao, r.get("household"), r.get("created_by")) || "Your co-parent";
        const what = group ? "swap" : "request";
        u.sendPush(dao, other,
            status === "accepted" ? "Agreement cancelled" : "Request withdrawn",
            `${who} cancelled the ${what} for ${u.fmtDay(r.get("date"))}`,
            { type: "custody_cancel" });
    } catch (err) { console.log("custody delete push error:", err); }
}, "custody_requests");

// ── expense_splits → push ────────────────────────────────────────────────────

// Create: notify the parent who owes a share.
onRecordAfterCreateRequest((e) => {
    const u = require(`${__hooks}/coplan_utils.js`);
    try {
        const dao = $app.dao();
        const r = e.record;
        const splitUser = r.get("user");
        if (!splitUser) return;

        u.sendPush(dao, splitUser, "New shared expense",
            `${u.expenseTitle(dao, r.get("expense"))} — your share is ${u.money(r.getInt("amount_due"))}`,
            { type: "expense_split", id: r.id });
    } catch (err) { console.log("expense create push error:", err); }
}, "expense_splits");

// Update → paid: receipt to the parent whose share was confirmed.
onRecordAfterUpdateRequest((e) => {
    const u = require(`${__hooks}/coplan_utils.js`);
    try {
        const dao = $app.dao();
        const r = e.record;
        if (r.get("status") !== "paid") return;
        if (r.originalCopy().get("status") === "paid") return;
        const splitUser = r.get("user");
        if (!splitUser) return;

        u.sendPush(dao, splitUser, "Payment confirmed",
            `Your ${u.money(r.getInt("amount_due"))} share of ${u.expenseTitle(dao, r.get("expense"))} was marked paid`,
            { type: "expense_paid", id: r.id });
    } catch (err) { console.log("expense paid push error:", err); }
}, "expense_splits");

// ── Self-test endpoint ───────────────────────────────────────────────────────
// POST /api/coplan/test-notification  → pushes a TEST notification to the
// caller's own registered devices. Used to verify the whole chain end-to-end
// (token registration → hook → sidecar → FCM → device) without creating junk
// custody/expense records. Returns how many tokens were targeted + the result.
routerAdd("POST", "/api/coplan/test-notification", (c) => {
    const u = require(`${__hooks}/coplan_utils.js`);
    const info = $apis.requestInfo(c);
    const authRecord = info.authRecord;
    if (!authRecord) throw new ForbiddenError("Authentication required.");

    const dao = $app.dao();
    const userId = authRecord.id;

    let tokenCount = 0;
    try { tokenCount = dao.findRecordsByFilter("device_tokens", "user = {:u}", "", 50, 0, { u: userId }).length; }
    catch (_) {}

    if (tokenCount === 0) {
        return c.json(200, {
            success: false,
            tokens: 0,
            message: "No registered devices for this user. Open the app (logged in) at least once to register a push token.",
        });
    }

    u.sendPush(dao, userId, "CoPlan test ✅",
        "If you can see this, push notifications are working.",
        { type: "test" });

    return c.json(200, { success: true, tokens: tokenCount });
});
