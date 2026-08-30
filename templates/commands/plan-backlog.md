Sweep an Azure DevOps backlog for Dev Ready user stories without child tasks and propose a single implementation task per story with an hour estimate. Usage: `/plan-backlog [project]`

This command walks the **backlog** of a chosen Azure DevOps project (work items not assigned to any sprint), finds user stories that are **Dev Ready**, **have Story Points**, and **have no child tasks yet**, and — story by story — proposes **one child Task** with an hour estimate for the user to approve before any work items are created. Exactly one task per story — never a multi-task breakdown.

Treat `$ARGUMENTS` as an optional project name (e.g. `/plan-backlog CSI Development`). If provided, skip the project prompt in Step 1.

## Step 1: Choose the Azure DevOps Project

### Detect the default project

Before prompting, attempt to detect the default Azure DevOps project from CLAUDE.md, in this order:

1. **Project CLAUDE.md** — read `<current-repo>/CLAUDE.md`. Look for an explicit `project: <name>` declaration, a "Work items live in **<Project Name>**" sentence, or a `## Pipeline Configuration` table with project references.
2. **Parent CLAUDE.md** — read `<parent-dir>/CLAUDE.md` (e.g. `~/Projects/CLAUDE.md`). Look for the same patterns. The CSI parent CLAUDE.md, for example, declares: "Work items for both **COMPASS** and **CSI Pay** live in the **CSI Development** Azure DevOps project."

If a default is found, present it pre-selected:

```
Which Azure DevOps project should I sweep?

  Default: {detected project}   ← press enter to accept

Or specify a different project name, or "list" to see all projects.
```

If the user types `list`, call `mcp__azure-devops__core_list_projects` and present the names, then re-prompt. **Wait for the user's response.** Validate the chosen project name exists (call `core_list_projects` if uncertain).

## Step 2: Query the Backlog

Run a WIQL query via `mcp__azure-devops__wit_query_by_wiql` to find candidate stories. "Backlog" means items at the **root iteration path** (not assigned to any sprint).

```sql
SELECT [System.Id], [System.Title], [System.State],
       [System.WorkItemType], [System.IterationPath],
       [Microsoft.VSTS.Scheduling.StoryPoints], [System.Tags]
FROM WorkItems
WHERE [System.TeamProject] = '{project}'
  AND [System.WorkItemType] IN ('User Story', 'Bug')
  AND [System.State] = 'Dev Ready'
  AND [Microsoft.VSTS.Scheduling.StoryPoints] > 0
  AND [System.IterationPath] = '{project}'
ORDER BY [Microsoft.VSTS.Common.StackRank] ASC
```

> The `[System.IterationPath] = '{project}'` clause restricts results to the **root** iteration — items not yet placed in a sprint. If a project uses a different convention (e.g. an explicit "Backlog" iteration), ask the user to confirm before proceeding.

If the query returns zero items, report:

```
No Dev Ready stories with Story Points were found on the backlog of {project}.
Nothing to plan.
```

and stop.

## Step 3: Filter Out Stories That Already Have Child Tasks

For each candidate from Step 2, fetch the work item with `mcp__azure-devops__wit_get_work_item` expanding `relations`. If the item has any `System.LinkTypes.Hierarchy-Forward` relation pointing at a `Task`, mark it as **already broken down** and skip it.

Present a one-line summary of what was skipped:

```
Skipped {n} stories that already have child tasks:
  - AB#{id}: {title}  ({k} existing tasks)
  - ...
```

If after filtering there are zero stories left, report "All Dev Ready backlog stories already have tasks — nothing to plan." and stop.

## Step 4: Present the Working List

Show the remaining stories the user is about to walk through:

```
Found {n} Dev Ready stories with Story Points and no child tasks on the {project} backlog:

| #  | ID       | Title                                    | Points |
|----|----------|------------------------------------------|--------|
| 1  | AB#4521  | COM - Admin can export payments to CSV   |   5    |
| 2  | AB#4523  | COM - Add bulk approval workflow         |   8    |
| 3  | AB#4530  | COM - Dashboard trend graphs             |   3    |
| .. | ...      | ...                                      |  ...   |

I'll walk through each one. For each story you'll see one proposed task
with an hour estimate; you can approve, edit, or skip per story.

Continue? (yes / cancel)
```

**Wait for the user.** If `cancel`, stop with no changes.

### Ultracode mode (optional fan-out)

Only when **ultracode is on** (a system-reminder confirms it, or the user typed `ultracode`): the analysis in 5a–5c is independent per story, so pre-compute all proposals in parallel with the `Workflow` tool instead of analyzing one story at a time.

- Fan out **one agent per story** that does 5a–5c — re-read the story, map points → band, judge complexity, pick within the band, draft the single task — and returns a structured proposal (story id, points, complexity, one-phrase complexity reason, band, and one `{title, hours}` task). Use a `schema` so each agent returns validated JSON, with `complexity` constrained to `low | medium | high`.
- Then run Step 5's loop **using the pre-computed proposals** — but keep 5d (approval) and 5e (creation) exactly as written: present each proposal, wait for `yes / edit / skip / cancel-all`, and create the task only after approval. **Never fan out the approval or the work-item creation** — those stay sequential and interactive.

If ultracode is off, ignore this and run Step 5 the normal sequential way. The output is identical either way; ultracode only makes the analysis faster for large backlogs.

## Step 5: Per-Story Task (loop)

For each remaining story, in order:

### 5a. Re-read the story in full

Fetch the work item again (Description and Acceptance Criteria fields) if not already cached. You need the AC text to write an accurate task title.

### 5b. Map Story Points → hour band, then pick within it by complexity

> **Assume a senior developer working with Claude assistance is the implementer.** The hour bands below already discount for both — no ramp-up time, no time spent learning the stack, routine cross-layer work is fast, and boilerplate/tests/mechanical refactors are assisted. Do not add a separate "experience" or "Claude" discount on top of these numbers.
>
> The hours that survive the assist are the human ones: understanding the requirement, the genuinely novel decisions, verification, review turnaround, and UAT. If a budget looks large only because the story touches many files, it's too large.

**Points give the band. Complexity picks the number inside it.** Never take the top of the band by default — that is what makes every estimate max out. Low complexity → the low end, medium → the middle, high → the high end.

Bands (calibrated for a senior developer with Claude assistance, at ~6 productive hours per day):

| Points | Low | Medium | High | Band in days (a day = 6 hrs) |
|--------|-----|--------|------|------------------------------|
| 1  |   1 |  1.5 |   2 | under 2 hours |
| 2  |   2 |  2.5 |   3 | 2 hours to half a day |
| 3  |   3 |    6 |  12 | half a day to two days |
| 5  |  12 |   18 |  24 | two to four days |
| 8  |  24 |   30 |  36 | around a week |
| 13 |  36 |   48 |  60 | one to two weeks — likely needs splitting |
| 21 |  60 |   75 |  90 | two to three weeks — almost certainly split |

The bands are **contiguous**: each one starts where the one below it ends, so a 1-pointer never costs more than a 2-pointer's floor. A day is **6 productive hours** and a week is **5 days (30 hours)** — every row above is a whole number of days once you leave the 1–2 point rows.

If the points value isn't on the Fibonacci scale, round to the nearest row above. Hours are rounded to the nearest half hour at 1–2 points and to a whole hour from 3 points up.

**Complexity is not size.** Points already carry the size — how much work there is. Complexity is how *hard* that work is: how many decisions are still open, how novel the shape is, how costly it is to get wrong. A large-but-boring story is high points at **low** complexity. Never default to the High column just because the points are high.

- **Low** — the shape is known before starting. One layer, or an existing pattern in the codebase to copy. AC is unambiguous. No new integration, no migration, no state or permission logic. Tests are mechanical.
- **Medium** — crosses layers, or touches an area with no exact precedent. A few real decisions, some edge cases to reason through, existing tests need reworking. This is the default when nothing pushes the item either way.
- **High** — novel design with nothing to copy; external or third-party contract; data migration or backfill; concurrency, state machines, permissions, money, or PII; ambiguous or self-contradicting AC; wide blast radius; behavior that is hard to verify.

Pick **one** band and hold a one-phrase reason for it — that phrase is shown with the proposal. When an item sits between two bands, take the **lower** one unless a High signal above is actually present.

Tags like `spike`, `research`, or `unknown-stack` are High-complexity signals on their own — use the High column for them rather than adding a separate percentage.

### 5c. Draft the single task

Create **exactly one task** covering all the work for the story — implementation, tests, code review revisions, and UAT support are all rolled into it. Do not split the story into design/backend/frontend/test tasks.

- **Title**: `{Prefix} - Implement: {short summary of the story}` — use the same product prefix as the parent (e.g. `COM`, `PAY`, `CDA`), extracted from the parent's title.
- **Hours**: the number picked in 5b — band from points, position in the band from complexity — rounded to a whole hour.

### 5d. Show the proposal

```
─────────────────────────────────────────────────────────────
AB#{id}: {title}      ({points} pts, {complexity} complexity → {budget} hrs)
─────────────────────────────────────────────────────────────

Proposed child task:

| Task title                                     | Hours |
|------------------------------------------------|-------|
| {Prefix} - Implement: payments CSV export      |  18   |

Complexity: medium — crosses API and client, follows the existing export pattern
Band for 5 pts: 12 / 18 / 24  (two to four days)

Approve? (yes / edit / skip / cancel-all)
```

**Wait for the user.**

- `yes` → proceed to 5e (create the task)
- `edit` → ask what to change (title or hours), revise, re-show, ask again
- `skip` → skip this story, move to the next; record it as skipped
- `cancel-all` → stop the entire loop with no further changes. Report what was already created.

### 5e. Create the child task

Create the approved task with `mcp__azure-devops__wit_create_work_item`:

- **project**: the chosen project
- **workItemType**: `Task`
- **title**: the task title (with prefix)
- **fields**:
  - `Microsoft.VSTS.Scheduling.OriginalEstimate` — the hour estimate (as a number)
  - `Microsoft.VSTS.Scheduling.RemainingWork` — the same hour estimate
  - `System.IterationPath` — copy from the parent (which is the root)
  - `System.AreaPath` — copy from the parent
  - `System.AssignedTo` — copy from the parent (pass the parent's `uniqueName` / email if its `System.AssignedTo` value is an identity object). If the parent is unassigned, leave this field unset rather than failing.

Then link the new task as a child of the parent with `mcp__azure-devops__wit_add_child_work_items` (or fall back to `wit_work_items_link` with link type `System.LinkTypes.Hierarchy-Forward` from parent → task).

If the create or link call fails, report the failure and ask the user whether to continue with the next story or abort the loop.

### 5f. Confirm per-story result

```
✓ AB#{id}: created 1 child task ({budget} hrs)
```

Then move to the next story.

## Step 6: Final Summary

Once the loop ends (all stories handled, or user said `cancel-all`):

```
## Backlog Planning Complete — {project}

Stories planned:    {n_planned}
  ✓ Tasks created:  {n_tasks_total} — one per story ({hours_total} hrs)
Stories skipped:    {n_skipped}
  - already had tasks: {n_existing}
  - user skipped:      {n_user_skipped}

Planned stories:
- AB#4521: 1 task, 24 hrs
- AB#4530: 1 task, 14 hrs
- ...

Next steps:
  /quote AB#{id}      — re-estimate any story whose budget felt off
  /implement AB#{id}  — start working on a planned story
```

Do not assign tasks, change parent state, or add tags unless the user explicitly asks — those are downstream decisions.
