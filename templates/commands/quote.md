Fetch a work item and estimate the effort in story points. Usage: `/quote <work-item-id>`

Parse `$ARGUMENTS` to extract the work item ID. Accept formats like `AB#1234`, `#1234`, or just `1234`.

## Step 1: Fetch the Work Item

Read the work item from Azure DevOps using the project from the current repo's CLAUDE.md configuration. Expand with `relations` to include child items and links.

If the work item is not found, report the error and stop.

Capture: title, type, description, acceptance criteria, repro steps (on a Bug), attached child items, any existing `Story Points` / `Effort` field value, and the item's **full current tag list** — both the tags that hint at scope (e.g. `spike`, `research`, `infra`) and the rest, because Step 5b appends to that list and must not clobber it.

## Step 2: Size the Work

Use the **modified Fibonacci scale** for story points: `1, 2, 3, 5, 8, 13, 21`. Anything that feels larger than 21 should be flagged as "needs to be split" rather than given a number.

> **Assume a senior developer working with Claude assistance is the implementer.** Don't pad for ramp-up, routine architectural decisions, or familiarity with the stack. A senior is expected to read the codebase, find existing patterns, and resolve ordinary unknowns without help — that effort is already priced into the rubric below. Only pad for things a senior *cannot* shortcut: genuinely novel work, missing AC, cross-team coordination, or external dependencies.

**Claude assistance is part of the baseline, so price these near the bottom of their range** — the rubric already assumes them, don't discount a second time:

- Boilerplate and scaffolding — DTOs, mappers, interfaces, request/response models, registrations.
- Writing tests for behavior that's already specified.
- Mechanical refactors, renames, and applying a known pattern across many files.
- CRUD endpoints, forms, tables, and screens that mirror something already in the repo.
- Migrations and scripts with an obvious shape.

**Volume of similar code is cheap.** A story whose size comes mostly from repetition — six more fields, four more columns, another slice of an existing pattern — should not earn points for its file count. Size it by the hardest distinct problem in it, not by how much typing it implies.

**Claude assistance does not compress these — never discount them:**

- Ambiguous, thin, or missing acceptance criteria (see the *not estimable* rule below).
- Genuinely novel design decisions with no precedent in the codebase.
- Third-party integrations, external APIs, and anything gated on another system's behavior.
- Cross-team coordination, sign-off, or a dependency on someone else's work landing first.
- Data migrations against production data, and anything needing a rollback plan.
- Security, compliance, or privacy review.
- Infrastructure, pipeline, and environment work that has to be verified by hand.
- Human wall-time: code review turnaround, UAT, and deploy gates.

These are what dominate an estimate at 8 points and above. If a big number is driven purely by code volume rather than by items on this list, the estimate is probably too high.

Rough sizing rubric (calibrated for a senior developer, assisted by Claude, working in a codebase they know):

| Points | Looks like |
|--------|-----------|
| **1** | Trivial change — copy tweak, single config value, one-line fix. No new tests needed. |
| **2** | Small, well-understood change in one file or one layer. Existing patterns cover it. |
| **3** | Touches a couple of files / one feature slice. Some new tests. No architectural questions. |
| **5** | Crosses layers (e.g. API + UI), or introduces a new component/endpoint following existing patterns. Real test coverage needed. |
| **8** | Multi-area change with meaningful new logic, migrations, or non-trivial edge cases. Unknowns a senior can resolve but that still take real wall-time. |
| **13** | Large feature, several moving parts, or significant unknowns even for a senior. Likely benefits from being split. |
| **21** | Very large / high uncertainty. Should almost certainly be split into multiple stories. |

Adjust upward for: unclear acceptance criteria, missing UX, data migrations, cross-team coordination, security/compliance review, or anything tagged `spike`/`research`.

Adjust downward for: pure config changes, mechanical refactors with good test coverage, work that mirrors an existing implementation, repetition of an established pattern, or anything where the senior will recognize the pattern immediately.

State the assist in the reasoning when it moved the number — e.g. "5 rather than 8: the three new endpoints follow `PaymentsController` exactly, so the volume is assisted work; the only real unknown is the reconciliation rule." That makes the estimate reviewable instead of asserted.

If the item has child items, size each child as well and present the parent's total as the sum (rounded to the nearest Fibonacci number).

**If the item can't be estimated at all, don't guess a number.** An item is *not estimable* when the gap is information only its creator can close — no acceptance criteria (or, on a Bug, no repro steps), a description that contradicts itself, scope you can't bound, or work that looks like it may already be done under another ticket. Report it as **needs more information**, list exactly what's missing, and go to Step 5 instead of Step 4. This is different from **needs to be split**: a split candidate is understood work that's simply too big, and it keeps its current state.

## Step 3: Display the Estimate

Output a compact estimate — not a quote block. Format:

```
**AB#{id}: {title}**
**Estimate:** {points} story points{ — confidence: low/medium/high}

**Reasoning:**
- {bullet on scope / files / layers touched}
- {bullet on unknowns or risk}
- {bullet on test/doc burden}

**Comparable to:** {one-line analogy to a similar past story, or "no obvious comparable in recent work"}
```

If child items were sized, append:

```
**Child breakdown:**
| AB# | Title | Points |
|-----|-------|--------|
| ... | ...   | ...    |
| **Total** |  | **{sum}** |
```

If an existing `Story Points` value is already set on the work item and your estimate differs, call that out explicitly: `**Existing estimate:** {n} (yours differs — {why})`.

If the work looks larger than 21 points, do not assign a number — instead report `**Estimate:** needs to be split` and suggest 2–4 candidate split points based on the acceptance criteria.

If the item isn't estimable, report that instead of a number:

```
**AB#{id}: {title}**
**Estimate:** needs more information

**Blocking:**
- {what's missing, and what you'd need to know to size it}
```

## Step 4: Offer to Persist (Points + Dev Ready)

This step applies when you produced a **number**. If the item was reported as *needs more information*, skip to Step 5.

After displaying the estimate, ask the user: *"Want me to set Story Points = {n} on AB#{id}? (This will also move it to Dev Ready.)"*

Only update the work item if the user explicitly says yes. Do not modify anything otherwise.

When the user agrees, in the **same** `wit_update_work_item` call:

1. Set `Microsoft.VSTS.Scheduling.StoryPoints` to the agreed value (the user's number wins if they adjusted it).
2. Set `System.State` to `Dev Ready` — **but only if** the work item type is `User Story`, `Bug`, or `Hot Fix` **and** the item is not already past Dev Ready in the workflow (e.g. `Active`, `Code Review`, `Ready to Deploy`). Never move an item backward — if it's already past Dev Ready, set the points only and mention the state was left alone.

**Never change the state of a Feature or a Task** — if the sized item is a Feature, persist points only (or per-child points on the children, each of which does get Dev Ready if it qualifies).

## Step 5: Offer to Take Unquotable Items Out of the Estimating Queue

When the item came out of Step 2 as **needs more information**, offer to drop it out of the estimating queue. **The mechanism depends on the work item type, because not every type has a design stage:**

| Type | Mechanism | Section |
|------|-----------|---------|
| `User Story` | Move `Design Approved` → **`Design Review`** | 5a |
| `Bug`, `Hot Fix` | Add a **`needs-info` tag**; leave the state at `New` | 5b |
| `Feature`, `Task` | Neither — report the gap and stop | — |

In the CSI Development process template, `Bug` and `Hot Fix` have **no design states at all** — the workflow is `New` → `Dev Ready` → `Active` → `Code Review` → …, with neither `Design Review` nor `Design Approved`. `New` is the bottom of that workflow, so there is nowhere to send a bug back to; the tag is what keeps `/quote-backlog` from re-analyzing it. On an unfamiliar project, confirm the type's real states with `mcp__azure-devops__wit_work_item` (`action: get_type`, `workItemType: Bug`) and read the `states` array — don't infer a state name from what the workflow "should" have. A bad state name is accepted by a query (zero rows, no error) and rejected only at write time.

### 5a. User Story → Design Review

> *"I can't size this until {what's missing}. Want me to move AB#{id} back to Design Review so it's out of the next `/quote-backlog` sweep until the creator responds?"*

**Wait for the user.** Only update the work item if they say yes. Then set `System.State` = `Design Review` with `mcp__azure-devops__wit_update_work_item`. Rules:

- **`User Story` only** — never a Bug, Hot Fix, Feature, or Task. A Bug takes 5b; the update would fail on it anyway.
- **Never move an item backward past the design stage.** Only from `Design Approved`; if it's already `Dev Ready` or anything at `Active` or later (`Active`, `Code Review`, `Ready for Testing`, `Testing`, `Ready to Deploy`, …), leave the state alone and say so — someone is already working on it, and a state bounce there does real damage.
- Already in `Design Review` → no-op; say it's already there.
- No `Design Review` state for `User Story` in this process template (the update returns an invalid-state error) → fall back in this order: `In Design` → the `needs-info` tag from 5b → leave the state alone and **warn** that the item will keep surfacing in backlog sweeps. Don't swallow the error.
- Set **no** story points and touch no other field — assignee, iteration, and tags stay as they are.

### 5b. Bug / Hot Fix → `needs-info` tag

> *"I can't size this until {what's missing} — and a Bug has no design state to send it back to. Want me to tag AB#{id} `needs-info` so it drops out of the next `/quote-backlog` sweep? Removing the tag re-queues it."*

**Wait for the user.** Only update the work item if they say yes. Then add the tag with `mcp__azure-devops__wit_update_work_item`. Rules:

- **Append to `System.Tags`, never replace it.** Take the current tag list captured in Step 1, append `needs-info`, and write the whole semicolon-separated list back. Writing the field bare wipes tags someone else set — `release-{N}`, triage labels, scope hints.
- Already tagged `needs-info` → no-op; say it's already there.
- **Leave `System.State` alone.** Never move the bug backward, and never move it to `Removed` or `Closed` — it is still a real bug, just not estimable yet.
- If the bug is at `Active` or later, someone is already working it: skip the tag, say so, and let them size it themselves.
- Set **no** story points and touch no other field — assignee, iteration, and state stay as they are.

Why either one matters: `/quote-backlog` sweeps unpointed User Stories in `Design Approved` and unpointed Bugs in `New`, excluding anything tagged `needs-info`. An item left untouched while waiting on its creator gets re-analyzed in every sweep — the state bounce (stories) and the tag (bugs) are what keep the next run reaching genuinely new items. Re-quote with `/quote AB#{id}` once the creator responds.

**Items that only need to be split keep their state and get no tag** — the work is understood, so there's nothing to send back. Same for an item where you got a number: that path ends at Step 4.
