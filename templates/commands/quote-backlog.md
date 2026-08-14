Sweep an Azure DevOps backlog for Design Approved stories without Story Points, review each for completeness and duplicate implementation, then — after user approval — set points and leave feedback comments for the item's creator. Usage: `/quote-backlog [project]`

This command walks the **backlog** of a chosen Azure DevOps project, finds user stories and bugs in **Design Approved** state that **have no Story Points yet**, and for each one:

1. **Reviews the work item for completeness** — description, acceptance criteria, title prefix, design links.
2. **Checks whether the work is already implemented** — in the codebase, in commits, or under another ticket.
3. **Looks at the code when it makes sense** — to validate the described approach and suggest changes.
4. **Proposes a story point estimate** — using the same senior-calibrated rubric as `/quote`.
5. **Drafts a comment for the item's creator** when issues are found.

**Hard batch limit: 10 items per run.** If more qualify, process the first 10 (by backlog rank) and report how many remain.

**Nothing is written to Azure DevOps — no points, no comments — until the user has seen the full batch and approved.** This command never modifies code, never changes work item state, and never reassigns items.

Treat `$ARGUMENTS` as an optional project name (e.g. `/quote-backlog CSI Development`). If provided, skip the project prompt in Step 1.

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

Run a WIQL query via `mcp__azure-devops__wit_query_by_wiql` to find candidate items. "Backlog" means items at the **root iteration path** (not assigned to any sprint).

```sql
SELECT [System.Id], [System.Title], [System.State],
       [System.WorkItemType], [System.IterationPath],
       [Microsoft.VSTS.Scheduling.StoryPoints], [System.Tags],
       [System.CreatedBy]
FROM WorkItems
WHERE [System.TeamProject] = '{project}'
  AND [System.WorkItemType] IN ('User Story', 'Bug')
  AND [System.State] = 'Design Approved'
  AND [Microsoft.VSTS.Scheduling.StoryPoints] = ''
  AND [System.IterationPath] = '{project}'
ORDER BY [Microsoft.VSTS.Common.StackRank] ASC
```

> The `[System.IterationPath] = '{project}'` clause restricts results to the **root** iteration — items not yet placed in a sprint. If a project uses a different convention (e.g. an explicit "Backlog" iteration), ask the user to confirm before proceeding.
>
> If the server rejects the empty-value comparison on Story Points, drop that clause, fetch the results, and filter out already-pointed items client-side.

**Take at most the first 10 items** (backlog-rank order). If the query returned more, note the overflow — it goes in the Step 4 header and the final summary.

If the query returns zero items, report:

```
No Design Approved items without Story Points were found on the backlog of {project}.
Nothing to quote.
```

and stop.

## Step 3: Analyze Each Item (max 10)

For each item in the batch, do all of 3a–3e before presenting anything. Collect results; **do not write to Azure DevOps during this step.**

### 3a. Fetch the full work item

Fetch with `mcp__azure-devops__wit_get_work_item` expanding `relations`. Capture: title, type, description, acceptance criteria, tags, `System.CreatedBy` (display name + unique name — needed for the comment draft), child items, and any linked PRs, commits, or branches.

### 3b. Completeness review

Score the item against this checklist:

| Check | What "complete" looks like |
|-------|---------------------------|
| **Title prefix** | Follows the project's `PREFIX - Title` convention (e.g. `COM -`, `PAY -`) |
| **Description** | States what is being built and why — not just a one-line restatement of the title |
| **Acceptance criteria** | Present, testable, unambiguous. Each AC could become a UAT step |
| **Design artifacts** | For UI work: a mockup, screenshot, or design link is attached or referenced (the item is Design Approved — the design should be findable) |
| **Scope** | Small enough to point (would land at ≤ 21); no hidden second feature buried in the AC |
| **Dependencies** | External dependencies or blockers are named, not implied |

Classify the item:

- **Complete** — estimable as written.
- **Minor gaps** — estimable, but the creator should clarify something (list the gaps).
- **Blocking gaps** — not estimable; missing AC, contradictory description, or unclear scope. No points will be proposed for this item.

### 3c. Duplicate / already-implemented check

Look for evidence the work already exists:

1. **Other tickets** — `mcp__azure-devops__search_workitem` with the item's key phrases. Flag closed or active items that describe the same functionality.
2. **The codebase** — `mcp__azure-devops__search_code` (and, if the current repo is the target codebase, local Grep) for the feature the item describes: endpoint names, component names, field names from the AC.
3. **Commits** — `mcp__azure-devops__repo_search_commits` for commit messages referencing the same feature or a `AB#` link to a related ticket.
4. **The item's own links** — existing PR/commit relations on the item itself are the strongest signal.

If the work appears already implemented, record **where** (ticket ID, PR, or file paths) — this goes in the comment draft, and no points are proposed until the creator confirms the item is still needed.

### 3d. Look at the code (when it makes sense)

If the target codebase is the current repo (or locally available) and the item describes concrete technical work, spend a short pass in the code:

- Confirm the described approach fits the existing architecture and patterns.
- Note anything that changes the estimate — e.g. the field already exists, a reusable component covers half the AC, or a migration will be needed that the item doesn't mention.
- If the item prescribes an approach the code contradicts, draft a **suggested change** for the comment (e.g. "the AC says add a new endpoint, but `PaymentsController` already exposes this — suggest extending it instead").

This is read-only reconnaissance. Skip it for non-technical items or when the codebase isn't available — say so in the item's analysis rather than guessing.

### 3e. Estimate story points

Use the **modified Fibonacci scale**: `1, 2, 3, 5, 8, 13, 21`. Anything larger than 21 is flagged as "needs to be split" rather than given a number.

> **Assume a senior developer is the implementer.** Don't pad for ramp-up, routine architectural decisions, or familiarity with the stack — that's already priced into the rubric. Only pad for things a senior *cannot* shortcut: genuinely novel work, missing AC, cross-team coordination, or external dependencies. Do not apply a second seniority discount on top of the rubric.

| Points | Looks like |
|--------|-----------|
| **1** | Trivial change — copy tweak, single config value, one-line fix |
| **2** | Small, well-understood change in one file or one layer |
| **3** | A couple of files / one feature slice, some new tests |
| **5** | Crosses layers, or a new component/endpoint following existing patterns |
| **8** | Multi-area change with real new logic, migrations, or non-trivial edge cases |
| **13** | Large feature, several moving parts — likely benefits from being split |
| **21** | Very large / high uncertainty — should almost certainly be split |

Fold in what 3d found — code reconnaissance that shrinks or grows the work changes the number. For items classified **Blocking gaps** or **appears already implemented**, propose **no points** — the comment is the deliverable for those.

### 3f. Draft the creator comment (only if issues were found)

If 3b–3d surfaced anything — gaps, a duplicate, a suggested approach change — draft a comment addressed to the item's creator (`System.CreatedBy`). Format:

```
@{Creator display name} — reviewed this item while estimating the backlog:

{One line per finding, concrete and actionable:}
- Acceptance criteria don't cover {X} — what should happen when {Y}?
- This looks already implemented in AB#{id} / PR #{n} ({file or feature}) — can you confirm it's still needed?
- Suggested approach change: {what the code shows, what to do instead}

{Closing line: what's needed to make it estimable, or "Estimated at {n} points assuming {assumption} — correct me if that's wrong."}
```

Keep it professional and brief — findings only, no filler. Items with no issues get **no comment**; don't post "looks good" noise.

### Ultracode mode (optional fan-out)

Only when **ultracode is on** (a system-reminder confirms it, or the user typed `ultracode`): the analysis in 3a–3f is independent per item, so fan out **one agent per item** with the `Workflow` tool. Each agent does the full 3a–3f pass and returns a structured result (item id, creator, completeness verdict, duplicate findings, code notes, proposed points, draft comment) — use a `schema` so each agent returns validated JSON.

**Never fan out Step 4 or Step 5** — presentation, approval, and every write stay sequential in the main loop. If ultracode is off, analyze the batch one item at a time; the output is identical either way.

## Step 4: Present the Batch — Approval Gate

Show the whole batch **before writing anything**. Start with the summary table:

```
Quote sweep — {project} backlog, Design Approved without Story Points
Batch: {n} of {total} qualifying items{ — run /quote-backlog again for the next 10}

| #  | ID       | Title                                  | Completeness  | Points | Comment |
|----|----------|----------------------------------------|---------------|--------|---------|
| 1  | AB#4611  | COM - Payment reminder emails          | Complete      |   5    | —       |
| 2  | AB#4614  | COM - Bulk close inactive accounts     | Minor gaps    |   8    | yes     |
| 3  | AB#4617  | PAY - Refund webhook handling          | Blocking gaps |   —    | yes     |
| 4  | AB#4620  | COM - Export audit log                 | Already done? |   —    | yes     |
```

Then a detail block per item — estimate reasoning (2–3 bullets), completeness findings, duplicate evidence with links/IDs, code notes, and the **full text of any draft comment**. The user must be able to read every word that would be posted.

Then ask:

```
Approve? (all / numbers e.g. "1,2,4" / edit N / skip N / cancel)
```

**Wait for the user.**

- `all` → apply every proposed write (points and comments) in Step 5
- `1,2,4` → apply only those items; the rest are recorded as skipped
- `edit N` → ask what to change on item N (points value or comment text), revise, re-show that item, ask again
- `skip N` → drop item N, re-ask for the rest
- `cancel` → stop with **zero changes** to Azure DevOps

## Step 5: Apply Approved Changes

Only for approved items, in batch order:

1. **Set Story Points** (items with a proposed number): update `Microsoft.VSTS.Scheduling.StoryPoints` via `mcp__azure-devops__wit_update_work_item`. Touch no other field — state, assignee, iteration, and tags stay as they are.
2. **Post the comment** (items with an approved draft): add it with `mcp__azure-devops__wit_add_work_item_comment` (or the server's work-item comment tool). Use the mention syntax the server supports so the creator is notified; otherwise lead with their display name as drafted.

If a write fails, report the failure and ask whether to continue with the remaining items or stop.

## Step 6: Final Summary

```
## Quote Sweep Complete — {project}

Items analyzed:   {n} (of {total} qualifying — {remaining} left for the next run)
  ✓ Points set:   {n_pointed}  (total {sum} pts)
  ✓ Comments:     {n_comments} posted to creators
  ⏭ Skipped:      {n_skipped} ({reasons: user skipped / blocking gaps / possible duplicate})

Pointed items:
- AB#4611: 5 pts
- AB#4614: 8 pts (comment posted)
- ...

Flagged for the creator (no points yet):
- AB#4617: blocking gaps — AC missing failure cases
- AB#4620: possibly already implemented in AB#4102

Next steps:
  /quote-backlog {project}   — process the next 10 qualifying items
  /quote AB#{id}             — re-estimate a single item after the creator responds
```

Do not change item state, create tasks, or assign items — those are downstream decisions (`/plan-backlog` picks up once items are pointed and Dev Ready).
