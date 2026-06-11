Sweep an Azure DevOps backlog for Dev Ready user stories without child tasks and propose a per-story task breakdown with hour estimates. Usage: `/plan-backlog [project]`

This command walks the **backlog** of a chosen Azure DevOps project (work items not assigned to any sprint), finds user stories that are **Dev Ready**, **have Story Points**, and **have no child tasks yet**, and — story by story — proposes a tailored Task breakdown with hour estimates for the user to approve before any work items are created.

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

I'll walk through each one. For each story you'll see a proposed task list
with hours; you can approve, edit, or skip per story.

Continue? (yes / cancel)
```

**Wait for the user.** If `cancel`, stop with no changes.

## Step 5: Per-Story Task Breakdown (loop)

For each remaining story, in order:

### 5a. Re-read the story in full

Fetch the work item again (Description and Acceptance Criteria fields) if not already cached. You need the AC text to tailor the task list.

### 5b. Map Story Points → total hour budget

> **Assume a senior developer is the implementer.** The hour budget below already discounts for senior-level speed — no ramp-up time, no time spent learning the stack, routine cross-layer work is fast. Do not add a separate "experience" discount on top of these numbers.

Use this mapping (calibrated for a senior developer at ~6 productive hours per day):

| Points | Hour budget | Notes |
|--------|-------------|-------|
| 1  |  3 hrs  | trivial change |
| 2  |  6 hrs  | small, one-layer change |
| 3  | 10 hrs  | one feature slice, modest tests |
| 5  | 16 hrs  | cross-layer or new component (routine for a senior) |
| 8  | 28 hrs  | multi-area, real unknowns even for a senior |
| 13 | 48 hrs  | large feature — should probably be split |
| 21 | 75 hrs  | very large — almost certainly split |

If the points value isn't on the Fibonacci scale, round to the nearest entry above. If the story has tags like `spike`, `research`, or `unknown-stack`, add 20–30% on top — those are the cases where seniority doesn't help.

### 5c. Tailor the task list (hybrid template)

Start from this template, then **add, remove, or rename** tasks based on what the AC actually describes:

| Default task           | When to include                                          |
|------------------------|----------------------------------------------------------|
| Design / Spike         | AC has open questions or the implementation isn't obvious |
| Backend implementation | AC mentions API, service, job, persistence, or data flow |
| Frontend implementation| AC mentions UI, screen, form, button, or workflow         |
| Database / migration   | AC requires schema changes or data backfill              |
| Automated tests        | Always include unless the story is purely a config tweak |
| Code review revisions  | Always include                                           |
| UAT support            | Always include unless explicitly out of scope            |

Distribute the hour budget across the chosen tasks. Reasonable defaults:

- Code review revisions: ~10% of budget (min 1 hr)
- UAT support: ~10% of budget (min 1 hr)
- Automated tests: ~15–25% of budget
- Design / Spike (if present): ~10–20% of budget
- Remaining hours split across implementation tasks based on the AC

Round each task to a whole hour. Final total should equal the budget (give or take 1 hr from rounding).

### 5d. Show the proposal

```
─────────────────────────────────────────────────────────────
AB#{id}: {title}      ({points} pts → {budget} hrs total)
─────────────────────────────────────────────────────────────

Proposed child tasks:

| # | Task title                                    | Hours |
|---|-----------------------------------------------|-------|
| 1 | {Prefix} - Design: clarify export field set   |   3   |
| 2 | {Prefix} - Backend: CSV export endpoint       |   8   |
| 3 | {Prefix} - Frontend: export button + download |   6   |
| 4 | {Prefix} - Tests: export endpoint + UI        |   4   |
| 5 | {Prefix} - Code review revisions              |   2   |
| 6 | {Prefix} - UAT support                        |   1   |
|   | **Total**                                     | **24**|

Approve? (yes / edit / skip / cancel-all)
```

Task titles use the same product prefix as the parent (e.g. `COM`, `PAY`, `CDA`) — extract it from the parent's title. Use the format `{Prefix} - {what the task does}`.

**Wait for the user.**

- `yes` → proceed to 5e (create the tasks)
- `edit` → ask which row to change (title or hours), revise, re-show the table, ask again
- `skip` → skip this story, move to the next; record it as skipped
- `cancel-all` → stop the entire loop with no further changes. Report what was already created.

### 5e. Create the child tasks

For each approved task, call `mcp__azure-devops__wit_create_work_item` with:

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

If any create or link call fails, report the failure for that task, stop creating tasks for this story, and ask the user whether to continue with the next story or abort the loop.

### 5f. Confirm per-story result

```
✓ AB#{id}: created {k} child tasks ({budget} hrs total)
```

Then move to the next story.

## Step 6: Final Summary

Once the loop ends (all stories handled, or user said `cancel-all`):

```
## Backlog Planning Complete — {project}

Stories planned:    {n_planned}
  ✓ Tasks created:  {n_tasks_total} ({hours_total} hrs)
Stories skipped:    {n_skipped}
  - already had tasks: {n_existing}
  - user skipped:      {n_user_skipped}

Planned stories:
- AB#4521: 6 tasks, 24 hrs
- AB#4530: 4 tasks, 14 hrs
- ...

Next steps:
  /quote AB#{id}      — re-estimate any story whose budget felt off
  /implement AB#{id}  — start working on a planned story
```

Do not assign tasks, change parent state, or add tags unless the user explicitly asks — those are downstream decisions.
