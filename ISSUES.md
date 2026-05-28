# Open Issues — Resolution-engine review

> ✅ **All issues resolved** — fixed in commits `ce1209c`, `0c95af4`, and subsequent
> roadmap commits. See individual GitHub issues for detailed fix descriptions.

Findings from the full logic audit of the schedule resolution engine. Also filed
as GitHub issues #1–#7 under the **"Resolution-engine review"** milestone:
<https://github.com/Pahiro/coplan/issues>

Severity key: 🟠 latent (bites the roadmap / a stray weekday rule, not today) ·
🟡 minor · 🟢 edge / perf.

| # | Title | Severity | Labels |
|---|---|---|---|
| 1 | DST drift in `weekOwner` rotation parity | 🟠 latent | bug, tech-debt |
| 2 | App engine vs freeze-cron conditional divergence | 🟠 latent | bug, tech-debt |
| 3 | Custody request overrides manual override inconsistently | 🟡 minor | bug |
| 4 | Per-child override doesn't cross-match "All" rules | 🟡 minor | enhancement, tech-debt |
| 5 | `parentFromString` silently defaults unknown → Jana | 🟡 robustness | bug, tech-debt |
| 6 | Calendar/recurring edge cases | 🟢 edge | bug |
| 7 | `effectiveCustodyFor` recomputation | 🟢 perf | performance, tech-debt |

The two worth fixing first are **#1** and **#2** — they're the ones that quietly
violate the "what you saw on the calendar == what gets frozen into history"
invariant the moment the roadmap (or a stray weekday rule) shows up.

---

## #1 — DST drift in `weekOwner` rotation parity (latent, multi-region)

**Severity:** latent — does not affect the current SAST deployment (South Africa has no DST).

**Location:** `lib/engine/resolution_engine.dart:46-51`

```dart
final weeks = monday.difference(anchorMonday).inDays ~/ 7;
return weeks.isEven ? Parent.bennet : Parent.jana;
```

**Problem:** `Duration.inDays` truncates. Across a DST boundary a true 7-day gap measures 167h, so `inDays` returns 6 and `6 ~/ 7 == 0` flips the parity. The `freezeRecurring` cron already uses UTC math, so in a DST timezone the **app-computed owner and the frozen-history owner could disagree**.

**Impact:** Wrong rotation owner (and thus wrong recurring expansion / frozen history) in any timezone that observes DST. Blocks the multi-region part of the roadmap (DESIGN §9.1).

**Suggested fix:** Count whole days via UTC or epoch math, e.g.
`(monday.toUtc().millisecondsSinceEpoch - anchorMonday.toUtc().millisecondsSinceEpoch) ~/ (7*86400000)`, with both pinned to UTC midnight.

---

## #2 — App engine and freeze cron use different day-owner conditionals

**Severity:** latent — currently harmless only because `custody_weekday_rules` is empty.

**Location:** `lib/engine/resolution_engine.dart:95` vs `backend/pb_hooks/main.pb.js` (`freezeRecurring`).

**Problem:** The live recurring expansion conditional uses `baseOwner(date)` = `weekdayRule ?? rotation`. The freeze cron uses rotation only (`weekOwner`). They are identical today only because no weekday rules exist. If anyone adds a `custody_weekday_rules` row, the app may expand a virtual occurrence that the cron then refuses to freeze (or vice versa).

**Impact:** Silently breaks the core invariant of the recurring design — *what you saw on the calendar == what gets frozen into history*.

**Suggested fix:** Make the cron mirror `baseOwner` (read weekday rules too), OR formally retire `custody_weekday_rules` so the two conditionals cannot diverge. Add a note in DESIGN that the two conditionals must stay identical.

---

## #3 — Custody request overrides a manual override inconsistently (mixed provenance)

**Severity:** minor / rare.

**Location:** `lib/engine/resolution_engine.dart:261-263`

```dart
final note = _custodyNoteAt(date, eventTime);
final actualParent = note != null ? parentAtTime(date, eventTime) : scheduleParent;
```

**Problem:** When an accepted custody request touches a slot, the responsible parent comes from `parentAtTime` (which ignores the manual override's `assignedParent`), but the event **time** and **reason** still come from the manual override. A single event can therefore show the override's time/reason with the transfer's parent.

**Impact:** Confusing mixed provenance when a manual override and a custody request coincide on the same slot.

**Suggested fix:** Decide explicitly which wins and apply it consistently (time, reason, and parent from the same source), or surface both clearly.

---

## #4 — Per-child override does not cross-match an "All" base rule

**Severity:** minor today; relevant for single-child / mixed families (DESIGN §9.1).

**Location:** `lib/engine/resolution_engine.dart:233-236`

```dart
final override = overrides.firstWhereOrNull((o) =>
    !o.isAdhoc &&
    _sameDay(o.targetDate, date) &&
    (o.childName == rule.childName || o.childName == 'All'));
```

**Problem:** A `Henri`-specific override does not modify an `All` base-rule event (and an `All` override does modify a `Henri` rule). Because each `ResolvedEvent` carries a single `assignedParent`, a child-specific override on an all-together activity is silently ignored.

**Impact:** Child-specific custody changes can't be expressed against shared events. Acceptable for the current always-together schedule; needs a model decision once families have mixed/independent children.

**Suggested fix:** Decide whether `All` events should split per child, or define explicit override-vs-rule child matching semantics.

---

## #5 — `parentFromString` silently defaults unknown names to Jana

**Severity:** robustness / latent (DESIGN §9.1).

**Location:** `lib/models/resolved_event.dart:20-21`

```dart
Parent parentFromString(String s) =>
    s == AppConstants.parentBennet ? Parent.bennet : Parent.jana;
```

**Problem:** Any string that is not exactly `"Bennet"` resolves to `Parent.jana` — including typos, empty strings, or a future third name. Data issues corrupt resolution invisibly.

**Impact:** Silent misattribution. Becomes a real hazard once parent names stop being hardcoded constants.

**Suggested fix:** Make parent identity data-driven (resolve against the household's users) and fail loudly / handle unknown explicitly rather than defaulting.

---

## #6 — Calendar/recurring edge cases (window+transfer, deleteForDay, freeze gap)

**Severity:** minor edge cases.

1. **Window + day-transfer on the same day** — `week_strip.dart` / `month_grid.dart` only render the window branch of the split, so a same-day day-transfer split is dropped. Day *colour* via `dayOwner` is still correct.
2. **`deleteForDay(weekday)`** (`schedule_provider.dart`) deletes every recurring arrangement on that weekday regardless of recipient — fine for two parents, loose for the future.
3. **Just-passed day** shows nothing in the ~5-minute window between local midnight and the 00:05 `freezeRecurring` cron run: the engine returns `[]` for past dates and the frozen row is not yet written.

**Suggested fixes:** handle both window and transfer in the split painter; scope `deleteForDay` by recipient/pattern; optionally have the engine fall back to live expansion for a just-passed day until the freeze catches up.

---

## #7 — Performance: `effectiveCustodyFor` recomputed repeatedly per day resolution

**Severity:** performance only (not correctness); negligible at current data volumes.

**Location:** `lib/engine/resolution_engine.dart` — `effectiveCustodyFor` / `_virtualRecurringFor`.

**Problem:** For each base-rule event, `effectiveCustodyFor` is re-filtered and the recurring list re-expanded ~4× (via `parentAtTime` and `_custodyNoteAt`, each calling `custodyWindows` and `dayTransferFor`). `_virtualRecurringFor` also calls `baseOwner(date)` twice per arrangement.

**Impact:** Wasted work that scales with events × arrangements. Fine now; worth addressing if days get busy or ranges get exported (DESIGN §9.4).

**Suggested fix:** Memoise `effectiveCustodyFor(date)` per `resolveDay` pass (or compute once and thread through), and compute `baseOwner(date)` once in `_virtualRecurringFor`.
