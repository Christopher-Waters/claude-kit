Sweep the **current sprint** for user stories and bugs without child tasks and propose a single implementation task per item with an hour estimate. Usage: `/plan-sprint [project]`

This command finds every **User Story** and **Bug** in the current sprint of a chosen Azure DevOps project that **has no child tasks yet**, and — item by item — proposes **one child Task** with an hour estimate for the user to approve before any work items are created. Exactly one task per work item — never a multi-task breakdown.

This is the sprint-planning counterpart of `/plan-backlog`. Use `/plan-backlog` to groom the unscheduled backlog; use `/plan-sprint` after items are pulled into the sprint to make sure each has its implementation task and hours.

Treat `$ARGUMENTS` as an optional project name (e.g. `/plan-sprint CSI Development`). If provided, skip the project prompt in Step 1.

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

## Step 2: Resolve the Current Sprint

Resolve the team's **current iteration** — do not guess the iteration path:

1. Determine the team. Most projects have a default team named after the project; if `mcp__azure-devops__core_list_project_teams` shows multiple teams and it isn't obvious which one runs the sprint, ask the user which team to use.
2. Fetch the current iteration via `mcp__azure-devops__work_list_team_iterations` (or the equivalent `work` tool) with `timeframe: current` and capture its full **iteration path** and date range.

If no current iteration exists (no sprint with today's date in range), report:

```
{project} has no active sprint (no iteration covers today). Nothing to plan.
```

and stop.

## Step 3: Query the Sprint

Run a WIQL query via `mcp__azure-devops__wit_query_by_wiql` using the **literal iteration path** from Step 2:

```sql
SELECT [System.Id], [System.Title], [System.State],
       [System.WorkItemType], [System.IterationPath],
       [Microsoft.VSTS.Scheduling.StoryPoints], [System.Tags]
FROM WorkItems
WHERE [System.TeamProject] = '{project}'
  AND [System.WorkItemType] IN ('User Story', 'Bug')
  AND [System.IterationPath] UNDER '{current sprint iteration path}'
  AND [System.State] NOT IN ('Closed', 'Removed', 'Done', 'Resolved', 'Code Review', 'Ready to Deploy', 'Deployed')
ORDER BY [Microsoft.VSTS.Common.StackRank] ASC
```

> The state exclusion drops items that are already implemented or finished — planning tasks for those adds noise. If the project's process template uses different late-stage state names, adjust the exclusion list to match; when in doubt, include the item and let the user skip it in Step 6.

Unlike `/plan-backlog`, **Story Points are not required** — an unpointed item that made it into the sprint still needs a task. Unpointed items are flagged in Step 5 and estimated from their description instead.

If the query returns zero items, report:

```
No open stories or bugs found in {current sprint} of {project}.
Nothing to plan.
```

and stop.

## Step 4: Filter Out Items That Already Have Child Tasks

For each candidate from Step 3, fetch the work item with `mcp__azure-devops__wit_get_work_item` expanding `relations`. If the item has any `System.LinkTypes.Hierarchy-Forward` relation pointing at a `Task`, mark it as **already broken down** and skip it.

Present a one-line summary of what was skipped:

```
Skipped {n} items that already have child tasks:
  - AB#{id}: {title}  ({k} existing tasks)
  - ...
```

If after filtering there are zero items left, report "Every open story and bug in {current sprint} already has a task — nothing to plan." and stop.

## Step 5: Present the Working List

Show the remaining items the user is about to walk through:

```
Found {n} items in {current sprint} ({date range}) with no child tasks:

| #  | ID       | Type       | Title                                    | State     | Points |
|----|----------|------------|------------------------------------------|-----------|--------|
| 1  | AB#4521  | User Story | COM - Admin can export payments to CSV   | Dev Ready |   5    |
| 2  | AB#4523  | Bug        | COM - Fix duplicate email on resend      | Active    |   —    |
| .. | ...      | ...        | ...                                      | ...       |  ...   |

I'll walk through each one. For each item you'll see one proposed task
with an hour estimate; you can approve, edit, or skip per item.

Continue? (yes / cancel)
```

**Wait for the user.** If `cancel`, stop with no changes.

### Ultracode mode (optional fan-out)

Only when **ultracode is on** (a system-reminder confirms it, or the user typed `ultracode`): the analysis in 6a–6c is independent per item, so pre-compute all proposals in parallel with the `Workflow` tool instead of analyzing one item at a time.

- Fan out **one agent per item** that does 6a–6c — re-read the item, derive the hour budget, draft the single task — and returns a structured proposal (item id, points, budget, and one `{title, hours}` task). Use a `schema` so each agent returns validated JSON.
- Then run Step 6's loop **using the pre-computed proposals** — but keep 6d (approval) and 6e (creation) exactly as written: present each proposal, wait for `yes / edit / skip / cancel-all`, and create the task only after approval. **Never fan out the approval or the work-item creation** — those stay sequential and interactive.

If ultracode is off, ignore this and run Step 6 the normal sequential way. The output is identical either way; ultracode only makes the analysis faster for large sprints.

## Step 6: Per-Item Task (loop)

For each remaining item, in order:

### 6a. Re-read the item in full

Fetch the work item again (Description and Acceptance Criteria fields — Repro Steps for Bugs) if not already cached. You need this text to write an accurate task title and, for unpointed items, an hour estimate.

### 6b. Derive the hour budget

> **Assume a senior developer working with Claude assistance is the implementer.** The hour budget below already discounts for both — no ramp-up time, no time spent learning the stack, routine cross-layer work is fast, and boilerplate/tests/mechanical refactors are assisted. Do not add a separate "experience" or "Claude" discount on top of these numbers.
>
> The hours that survive the assist are the human ones: understanding the requirement, the genuinely novel decisions, verification, review turnaround, and UAT. If a budget looks large only because the story touches many files, it's too large.

**If the item has Story Points**, use this mapping (calibrated for a senior developer with Claude assistance, at ~6 productive hours per day):

| Points | Hour budget | Notes |
|--------|-------------|-------|
| 1  |  3 hrs  | trivial change |
| 2  |  6 hrs  | small, one-layer change |
| 3  | 10 hrs  | one feature slice, modest tests |
| 5  | 16 hrs  | cross-layer or new component (routine for an assisted senior) |
| 8  | 28 hrs  | multi-area, real unknowns the assist doesn’t remove |
| 13 | 48 hrs  | large feature — should probably be split |
| 21 | 75 hrs  | very large — almost certainly split |

If the points value isn't on the Fibonacci scale, round to the nearest entry above. If the item has tags like `spike`, `research`, or `unknown-stack`, add 20–30% on top — those are the cases where neither seniority nor the assist helps.

**If the item has no Story Points**, estimate the hours directly from the description, acceptance criteria, and repro steps — judge which row of the table the work most resembles and use that hour budget. Mark the proposal `(no points — estimated from description)` and suggest `/quote AB#{id}` in the final summary. Do **not** set Story Points on the item — that's the user's call.

### 6c. Draft the single task

Create **exactly one task** covering all the work for the item — implementation, tests, code review revisions, and UAT support are all rolled into it. Do not split the item into design/backend/frontend/test tasks.

- **Title**: `{Prefix} - Implement: {short summary of the item}` — use the same product prefix as the parent (e.g. `COM`, `PAY`, `CDA`), extracted from the parent's title. For Bugs, `{Prefix} - Fix: {short summary}` reads better.
- **Hours**: the full hour budget from 6b, rounded to a whole hour.

### 6d. Show the proposal

```
─────────────────────────────────────────────────────────────
AB#{id}: {title}      ({points} pts → {budget} hrs)
─────────────────────────────────────────────────────────────

Proposed child task:

| Task title                                     | Hours |
|------------------------------------------------|-------|
| {Prefix} - Implement: payments CSV export      |  24   |

Approve? (yes / edit / skip / cancel-all)
```

For unpointed items, the header line reads `(no points — estimated from description → {budget} hrs)`.

**Wait for the user.**

- `yes` → proceed to 6e (create the task)
- `edit` → ask what to change (title or hours), revise, re-show, ask again
- `skip` → skip this item, move to the next; record it as skipped
- `cancel-all` → stop the entire loop with no further changes. Report what was already created.

### 6e. Create the child task

Create the approved task with `mcp__azure-devops__wit_create_work_item`:

- **project**: the chosen project
- **workItemType**: `Task`
- **title**: the task title (with prefix)
- **fields**:
  - `Microsoft.VSTS.Scheduling.OriginalEstimate` — the hour estimate (as a number)
  - `Microsoft.VSTS.Scheduling.RemainingWork` — the same hour estimate
  - `System.IterationPath` — copy from the parent (the parent is in the current sprint, so the task lands on the sprint taskboard)
  - `System.AreaPath` — copy from the parent
  - `System.AssignedTo` — copy from the parent (pass the parent's `uniqueName` / email if its `System.AssignedTo` value is an identity object). If the parent is unassigned, leave this field unset rather than failing.

Then link the new task as a child of the parent with `mcp__azure-devops__wit_add_child_work_items` (or fall back to `wit_work_items_link` with link type `System.LinkTypes.Hierarchy-Forward` from parent → task).

If the create or link call fails, report the failure and ask the user whether to continue with the next item or abort the loop.

### 6f. Confirm per-item result

```
✓ AB#{id}: created 1 child task ({budget} hrs)
```

Then move to the next item.

## Step 7: Final Summary

Once the loop ends (all items handled, or user said `cancel-all`):

```
## Sprint Planning Complete — {project} / {current sprint}

Items planned:      {n_planned}
  ✓ Tasks created:  {n_tasks_total} — one per item ({hours_total} hrs)
Items skipped:      {n_skipped}
  - already had tasks: {n_existing}
  - user skipped:      {n_user_skipped}

Planned items:
- AB#4521: 1 task, 24 hrs
- AB#4523: 1 task, 6 hrs  (no points — consider /quote AB#4523)
- ...

Next steps:
  /quote AB#{id}      — point any unpointed item or re-check a budget that felt off
  /implement AB#{id}  — start working on a planned item
```

Do not assign tasks, change parent state, set story points, or add tags unless the user explicitly asks — those are downstream decisions.
