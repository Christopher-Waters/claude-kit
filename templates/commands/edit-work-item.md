Edit an existing Azure DevOps work item. Usage: `/edit-work-item <work-item-id> [what to change]`

This command revises a work item that already exists — title, description, acceptance criteria, points, priority/severity, order. On a **Feature** it treats the Feature and its child User Stories as **one unit**: a change to the Feature's scope cascades into the children, new stories are drafted for new scope, stories that fell out of scope are retired, and `Custom.Order` is re-sequenced so the implementation waves still make sense.

Parse `$ARGUMENTS`:
- **Work item ID** — accept `AB#1234`, `#1234`, or `1234`. Required. If missing, ask for it and stop.
- **Change request** — any remaining text is the user's description of what to change (e.g. `/edit-work-item AB#6240 add SSO to the scope, drop the CSV export story`). Optional — if absent, Step 3 asks for it.
- **`--dry-run`** — do every step including the full change set, but make no writes. Report what would have changed and stop.

## Step 1: Fetch the Work Item

Read the work item with `expand: Relations` so links and children come back. Collect:

- `System.Title`, `System.WorkItemType`, `System.State`, `System.AssignedTo`, `System.Tags`
- `System.Description`, `Microsoft.VSTS.Common.AcceptanceCriteria`
- `Microsoft.VSTS.Scheduling.StoryPoints`, `Custom.Order`
- For Bugs / Hot Fixes: `Microsoft.VSTS.TCM.ReproSteps`, `Microsoft.VSTS.Common.Priority`, `Microsoft.VSTS.Common.Severity`
- Parent, children, and **linked pull requests** (`ArtifactLink` relations)
- Comments — recent discussion often explains why a field says what it says

If the work item is not found, report the error and stop.

### If the item is a Feature

Also fetch every child via `wit_work_item` `get_batch` with fields `System.Id`, `System.Title`, `System.WorkItemType`, `System.State`, `System.AssignedTo`, `Custom.Order`, `Microsoft.VSTS.Scheduling.StoryPoints`, `System.Description`, `Microsoft.VSTS.Common.AcceptanceCriteria`. Children are the `System.LinkTypes.Hierarchy-Forward` relations. You need their full text — you cannot judge whether a story still fits the revised scope from its title alone.

## Step 2: Show the Current Item

Present what exists today, so the user is editing against reality and not memory:

```
## AB#{id}: {title}

**Type:** {type}   **State:** {state}   **Points:** {n | not set}   **Assigned:** {name | unassigned}
**Linked PRs:** {#id (status), ... | none}

### Description
{current description, rendered as readable text}

### Acceptance Criteria
{current AC}
{for Bugs:}
**Priority:** {n}   **Severity:** {n - Label}
{end for Bugs}
```

**Two things read as "this item has acceptance criteria" when it doesn't.** Check for both before showing the item, and say plainly which one you found:

- **The field holds the process template's placeholder** — tip text like `💡 Tip: Add "@serena rewrite" to Description for AI suggestions  Define acceptance criteria: - [ ]  - [ ]  - [ ]`. Treat that as **empty** and display it as `(none — placeholder text only)`.
- **The criteria are in `System.Description`** under an "Acceptance Criteria" heading, with the real field empty or placeholder-filled. This is the misfiled case. Display the criteria where they actually live, flag it, and offer the repair described in Step 7 — moving them costs the user nothing and unblocks estimation.

For a **Feature**, append the current wave layout:

```
### Child Stories (current Custom.Order waves)

| Wave | Order | Story | Title | Points | State |
|------|-------|-------|-------|--------|-------|
| 1 | 1 | AB#6242 | ... | 3 | Dev Ready |
| 1 | 1 | AB#6243 | ... | 2 | Dev Ready |
| 2 | 2 | AB#6244 | ... | 5 | Code Review |
| 3 | — | AB#6245 | ... | 3 | New |  ← no Custom.Order set
```

## Step 3: Gather the Change Request

If the user supplied a change request inline, restate your reading of it in one line and move on. Otherwise ask:

```
What should change on AB#{id}?

Describe it however you like — "the scope should also cover SSO", "tighten AC 3",
"this is really two stories", "bump severity to 2". You can paste image URLs or
links; they'll be preserved.
```

**Wait for the user's response.** Ask at most one targeted clarifying question if the request is ambiguous about *which* field or *which* child it touches.

Scan the response for images and links and preserve them exactly as `/create-work-item` Step 2 describes — an edit must never silently strip an image, attachment URL, or reference link that is already in the description.

## Step 4: Draft the Change Set

Produce a **field-level diff**, not a rewritten item. For every field you propose to touch, show before and after. Fields not listed are not touched.

```
## Proposed Changes — AB#{id}

**Title**
  - {current}
  + {proposed}

**Description**
  {a readable summary of what's being added, removed, or reworded — not a raw dump}

**Acceptance Criteria**
  - 3. {removed criterion}
  + 3. {new criterion}
  + 4. {added criterion}

**Story Points:** {n} → {m}   ({one-line rationale})
**Priority / Severity:** {n} → {m}   (Bugs only)

**Unchanged:** {list the fields you deliberately left alone}
```

Rules for the draft:

- **Preserve, don't regenerate.** Keep existing wording that the change request doesn't touch. Never drop existing `<img>` tags, attachment URLs, or reference links.
- **Points follow the `/quote` rubric** — modified Fibonacci (`1, 2, 3, 5, 8, 13, 21`), calibrated for a senior developer working with Claude assistance. Only propose a change if the scope actually moved. If the revised item now looks bigger than 21 points, recommend splitting it into a Feature instead of writing the number.
- **Never point a Feature** and never change a Feature's `System.State`.
- **Prefix rule holds** — if the title changes, it keeps its `PREFIX - ` prefix from the project's CLAUDE.md table.

### If the item is a Feature — cascade to the children

This is the point of the command. After drafting the Feature's own changes, evaluate **every child story against the revised scope** and classify each one:

| Verdict | Meaning | Action |
|---------|---------|--------|
| **Unchanged** | Still correct under the new scope | Leave it entirely alone |
| **Update** | Still belongs, but its title / description / AC / points no longer match | Draft a field-level diff for it |
| **Add** | The revised scope introduces work no existing story covers | Draft a new User Story (`/create-work-item` Step 3 shape) with proposed points |
| **Retire** | The revised scope no longer includes this work | Propose `System.State` = `Removed`, or unlinking from the Feature — user picks |
| **Split** | The story now carries two independently shippable slices | Propose narrowing the existing story and adding a sibling |

Then **re-sequence `Custom.Order`**, because adding, retiring, or re-scoping stories usually breaks the wave plan:

1. Rebuild the dependency picture across the surviving + added stories: a story that needs another story's work merged first must land in a **later** wave.
2. Stories with no dependency on each other share a wave (same `Custom.Order` value) so `/implement` runs them in parallel.
3. Number waves as **consecutive integers starting at 1**, no gaps. Stories that previously had no `Custom.Order` get one now.
4. **Only write `Custom.Order` where the value actually changes.** A re-sequence that renumbers every story to the same value it already had is not a change — don't issue the write.
5. Stories already past `Dev Ready` (see the safety gate below) keep their existing order unless the user explicitly says otherwise — moving an in-flight story between waves has no effect on work that's already done and only confuses the record.

Present the cascade as one table, old order → new order:

```
### Child Story Changes

| Story | Title | Verdict | Order | Points | State | Notes |
|-------|-------|---------|-------|--------|-------|-------|
| AB#6242 | ... | Unchanged | 1 | 3 | Dev Ready | — |
| AB#6243 | ... | Update    | 1 | 2 → 3 | Dev Ready | AC 2 reworded for SSO |
| AB#6244 | ... | Unchanged | 2 → 2 | 5 | Code Review | in flight — order held |
| (new)   | ... | Add       | 2 | 5 | → Dev Ready | covers new SSO scope |
| AB#6245 | ... | Retire    | — | 3 | New | dropped from scope → Removed |

### Resulting Waves

| Wave | Order | Stories |
|------|-------|---------|
| 1 | 1 | AB#6242, AB#6243 |
| 2 | 2 | AB#6244, (new SSO story) |
```

Show the field-level diff for every story marked **Update**, and the full draft for every story marked **Add**, below the table. The user is approving specific text, not a summary.

## Step 5: Safety Gate — In-Flight Work

Before asking for approval, check the state of everything you propose to write and flag anything that is **past `Dev Ready`** in the workflow (`Active`, `Code Review`, `Ready for Testing`, `Testing`, `Ready to Deploy`, `Deployed`, `Closed`) or has a **linked pull request**.

Editing the acceptance criteria of a story that is already implemented silently invalidates a PR that was reviewed against the old criteria. So for each such item, call it out explicitly:

```
⚠️  AB#6244 is in **Code Review** with PR #142 open.

Changing its acceptance criteria now means the open PR no longer matches the story.
  1. Edit it anyway — I'll note the change in a work item comment
  2. Leave it alone and put the new behavior in a new story
  3. Use /rework AB#6244 instead — that's the flow built for post-PR changes

Which?
```

**Wait for the user on each flagged item.** Default to option 2 if the user is vague — adding a story is always recoverable; rewriting an implemented one is not.

Never move an item **backward** through the workflow. If setting points on an item that is already past `Dev Ready`, set the points only, leave the state alone, and say so.

## Step 6: Approve

```
## Ready to Apply — AB#{id}

**Feature/item changes:** {n} field(s)
**Child stories:** {a} updated, {b} added, {c} retired, {d} re-ordered, {e} unchanged
**In-flight items being edited:** {list | none}
**Post a comment recording this change on each edited item?** {yes | no}

Apply these changes? (yes / edit / cancel)
```

**Wait for the user.**
- `yes` → Step 7
- `edit` → ask which part to revise, revise it, re-show the diff from Step 4, then return here
- `cancel` → abort with no writes and confirm "Cancelled — nothing was changed."

If `--dry-run` was passed, stop here instead and report the change set as final output. Make no writes.

Default the comment question to **yes** for any item past `New`, and **no** for items still in `New` (nobody has looked at them yet).

## Step 7: Apply

Render every Markdown section to HTML first — Azure DevOps description and acceptance criteria fields do not render Markdown. Use the conversion table and the **emphasis and code spans** rules from `/create-work-item` Step 8: bold the noun phrase carrying each claim, wrap identifiers in `<code>`, use lists for 2+ parallel items, keep `### Headings` as `<h3>`. Preserve existing `<img>` tags exactly.

**Route each section to its own field**, per the field-routing table in `/create-work-item` Step 8. The rule that matters most here: **acceptance criteria go in `Microsoft.VSTS.Common.AcceptanceCriteria`, never in `System.Description`.** When you rewrite AC, write the criteria list alone into that field — no `<h3>Acceptance Criteria</h3>` wrapper — and make sure the description you write back carries no copy of them. Editing an item is the moment this gets silently undone: it is easy to render the whole reviewed document into the description and leave the AC field as it was.

**Repair misfiled criteria when you find them.** If Step 2 found the criteria living in the description (or the AC field holding only placeholder tip text), fix it as part of this edit even when the user didn't ask — it is the same content, moved to the field Azure DevOps and every kit sweep actually read:

- Write the criteria into `Microsoft.VSTS.Common.AcceptanceCriteria`, overwriting the placeholder.
- Strip the "Acceptance Criteria" heading and its list out of `System.Description` in the same call, so the two fields don't both hold a copy.
- Say so in the change set and in the Step 8 confirmation: `Acceptance criteria: moved from Description → AC field (3 criteria)`. Never move criteria silently; the user needs to see that the description shrank.
- This is a **move, not a rewrite** — the criteria text is unchanged unless the user separately approved a reword.

Apply writes in this order, so a failure partway through leaves the most useful state behind:

1. **Update the parent item** — one `mcp__azure-devops__wit_update_work_item` call with every changed field. Never include `System.State` for a Feature.
2. **Update existing children** (verdict `Update`) — one call per story, points and `Custom.Order` in the same call as the text changes. If points were set on a story still at or before `Dev Ready`, set `System.State` = `Dev Ready` in that same call.
3. **Create added children** — `mcp__azure-devops__wit_create_work_item` with description, acceptance criteria, `Custom.Order`, agreed `Microsoft.VSTS.Scheduling.StoryPoints`, and `System.AssignedTo` copied from the Feature if it has an assignee. Then link each to the Feature as a child via `mcp__azure-devops__wit_work_item_link_write` (`System.LinkTypes.Hierarchy-Reverse`), then move pointed ones to `Dev Ready` in a follow-up call.
4. **Re-order** any story whose only change is `Custom.Order` — one call each, touching that field alone.
5. **Retire** stories the user approved — set `System.State` = `Removed`, or remove the parent link, whichever the user chose. **Never delete a work item.**
6. **Post comments** (if the user said yes) via `mcp__azure-devops__wit_work_item_comment_write` — one short comment per edited item saying what changed and why, and naming the Feature edit that drove it (e.g. `Scope updated via edit of AB#6240: acceptance criteria 2 reworded to cover SSO; re-ordered from wave 3 to wave 2.`).

Touch no field that wasn't in the approved change set. Assignee, iteration, and tags stay as they are unless the user asked.

If any write fails, stop, report exactly which items were changed and which weren't, and do not retry blindly — a half-applied re-sequence needs the user to see the real state before you try again.

## Step 8: Confirm

```
Updated AB#{id}: {title}
  Type: {type}
  Fields changed: {list}
  Points: {n → m | unchanged}
  State: {state} {(unchanged — Features are never moved) | (→ Dev Ready)}
  URL: {work item URL}

{Features only:}
  Child stories:
    updated:   AB#{id} ({what changed})
    added:     AB#{id} — {title} (order {n}, {p} pts, Dev Ready)
    retired:   AB#{id} — {title} (Removed)
    re-ordered: AB#{id} (wave {old} → {new})
    unchanged: {count}

  Resulting waves: {1: AB#..., AB#... | 2: AB#...}
{end Features only}

Next steps:
  /explain AB#{id}     — re-read the item as it now stands
  /implement AB#{id}   — {implement the child stories in Custom.Order waves | start working on it}
```

If nothing ended up changing (the user cancelled every proposed edit at the safety gate), say that plainly rather than reporting a successful edit.
