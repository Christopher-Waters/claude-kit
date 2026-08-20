Sweep an Azure DevOps backlog for Design Approved stories without Story Points, review each for completeness and duplicate implementation, then — after user approval — set points and leave feedback comments for the item's creator. Usage: `/quote-backlog [project]`

This command walks the **backlog** of a chosen Azure DevOps project, finds user stories and bugs in **Design Approved** state that **have no Story Points yet**, and for each one:

1. **Reviews the work item for completeness** — description, acceptance criteria, title prefix, design links.
2. **Checks whether the work is already implemented** — in the codebase, in commits, or under another ticket.
3. **Looks at the code when it makes sense** — to validate the described approach and suggest changes.
4. **Proposes a story point estimate** — using the same senior-calibrated rubric as `/quote`.
5. **Drafts a comment for the item's creator** when issues are found.
6. **Suggests a rewrite of the description, and of existing acceptance criteria,** when they need work — offered to the creator in the comment, or applied directly if the user chooses.

**Never author acceptance criteria from nothing.** The rewrite improves AC that are *already there* — it never fills an empty AC field. If the item has no acceptance criteria, the deliverable is a comment telling the creator the AC are missing and the item can't be estimated without them. Rewriting someone's AC is editing their intent; writing AC for a blank field is inventing it.

**Hard batch limit: 10 items per run.** If more qualify, process the first 10 (by backlog rank) and report how many remain.

**Nothing is written to Azure DevOps — no points, no comments — until the user has seen the full batch and approved.** This command never modifies code and never reassigns items. The only state change it makes: when approved points are written to an item, that item also moves to **Dev Ready** (see Step 5).

Treat `$ARGUMENTS` as an optional project name (e.g. `/quote-backlog CSI Development`). If provided, skip the project prompt in Step 1.

## `--help`

If `$ARGUMENTS` contains `--help` or `-h`, print everything between the two rules below **as markdown — the table must render as a table, not inside a code fence** — then **stop**. Run no query, fetch no work items, write nothing.

---

**`/quote-backlog [project]`** — sweep a backlog for Design Approved items with no Story Points.

Reviews each item for completeness and duplicate work, proposes points, and drafts feedback for the item's creator. Max 10 items per run, in backlog-rank order.

Nothing is written to Azure DevOps until you approve the batch — every option below is a fully reversible choice.

| You type | What happens |
|----------|--------------|
| `all` | Everything proposed gets applied |
| `1,2,4` | Only those numbered items get applied; the rest are recorded as skipped |
| `edit N` | I pause on item N so you can change my proposal, then re-show it |
| `skip N` | Item N is dropped from the batch; I re-ask about the rest |
| `apply rewrite N` | Item N's rewrite is written **onto the work item** instead of only suggested |
| `cancel` | Stop with zero changes |

Numbers refer to the `#` column of the summary table, not to AB# ids — so `1,2,10` acts on items 1, 2 and 10 of the batch and leaves everything else untouched.

**What approval writes:**
- **Story Points** on items that got a number — each also moves from Design Approved to **Dev Ready**
- **Comments** to the creators of items where something was found
- **Rewrites** — description, and a tightened version of AC that already exist — only for items you explicitly marked `apply rewrite N`

**AC are never written from scratch.** Existing acceptance criteria can be rewritten to be clearer or testable, but an empty AC field is left empty — the creator is told it's missing and that the item can't be estimated without it.

---

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
| **Acceptance criteria** | Present, testable, unambiguous. Each AC could become a UAT step. Record whether the field is **empty** or merely **weak** — that distinction decides whether AC can be rewritten (3g) or must go back to the creator (3f) |
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

> **Assume a senior developer working with Claude assistance is the implementer.** Don't pad for ramp-up, routine architectural decisions, or familiarity with the stack — that's already priced into the rubric. Only pad for things a senior *cannot* shortcut: genuinely novel work, missing AC, cross-team coordination, or external dependencies. Do not apply a second seniority discount on top of the rubric.

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
- AC #{n} isn't testable as written ({why}) — what does "done" look like for it?
- The AC are missing the steps for {flow} — {what a tester couldn't verify from them}
- This looks already implemented in AB#{id} / PR #{n} ({file or feature}) — can you confirm it's still needed?
- Suggested approach change: {what the code shows, what to do instead}

{Closing line: what's needed to make it estimable, or "Estimated at {n} points assuming {assumption} — correct me if that's wrong."}
```

**When the AC field is empty, report it — don't fill it.** Say the acceptance criteria are missing and that the item can't be estimated without them, and ask the creator for them. Never follow that with a drafted list, a "here's a starting point:" section, or criteria inferred from the title. Existing AC are a different case — those can be rewritten in 3g.

Keep it professional and brief — findings only, no filler. Items with no issues get **no comment**; don't post "looks good" noise.

### 3g. Draft a suggested rewrite (when needed)

If the completeness review found the **description** or the **existing acceptance criteria** to be vague, contradictory, or structurally weak — not just missing one detail — draft a rewrite that preserves the creator's intent:

- **Description**: what is being built, why, and for whom — written from what the item, its links, and the code reconnaissance establish. Never invent requirements; where intent is unknowable, leave an explicit `{question for creator}` placeholder instead of guessing.
- **Acceptance criteria** — **only when the item already has some.** Restructure what's there into a numbered, testable list: split compound criteria, make vague ones verifiable, drop duplicates, and flag contradictions. Every criterion must trace back to something the creator already wrote; a gap the existing AC don't address stays a `{question for creator}` placeholder, not a new criterion you supply.
- **Title**: only if it violates the `PREFIX - Title` convention or misdescribes the work.

**An empty AC field is never filled.** If the item has no acceptance criteria at all, the rewrite covers description and title only — leave AC out of the suggested text entirely and let the comment (3f) ask the creator to write them. Don't route around this by putting criteria in the description as a "should" list.

The rewrite is a *suggestion*: by default it travels inside the creator comment (3f) under a "Suggested rewrite:" heading so the creator stays in control of their item. It is applied directly to the work item only if the user explicitly chooses that in Step 4. Skip this for items that are Complete or only missing a one-line answer — a rewrite should earn its place.

### Ultracode mode (optional fan-out)

Only when **ultracode is on** (a system-reminder confirms it, or the user typed `ultracode`): the analysis in 3a–3g is independent per item, so fan out **one agent per item** with the `Workflow` tool. Each agent does the full 3a–3g pass and returns a structured result (item id, creator, completeness verdict, duplicate findings, code notes, proposed points, draft comment, suggested rewrite) — use a `schema` so each agent returns validated JSON.

**Never fan out Step 4 or Step 5** — presentation, approval, and every write stay sequential in the main loop. If ultracode is off, analyze the batch one item at a time; the output is identical either way.

## Step 4: Present the Batch — Approval Gate

Show the whole batch **before writing anything**. Start with the summary table:

```
Quote sweep — {project} backlog, Design Approved without Story Points
Batch: {n} of {total} qualifying items{ — run /quote-backlog again for the next 10}

| #  | ID       | Title                                  | Completeness  | Points | Comment | Rewrite |
|----|----------|----------------------------------------|---------------|--------|---------|---------|
| 1  | AB#4611  | COM - Payment reminder emails          | Complete      |   5    | —       | —       |
| 2  | AB#4614  | COM - Bulk close inactive accounts     | Minor gaps    |   8    | yes     | —       |
| 3  | AB#4617  | PAY - Refund webhook handling          | Blocking gaps |   —    | yes     | yes     |
| 4  | AB#4620  | COM - Export audit log                 | Already done? |   —    | yes     | —       |
```

Then a detail block per item — estimate reasoning (2–3 bullets), completeness findings, duplicate evidence with links/IDs, code notes, the **full text of any draft comment**, and the **full text of any suggested rewrite**. The user must be able to read every word that would be posted.

Note above the prompt: **items that get points will also move to Dev Ready** — approving the points approves the state change.

Then ask:

```
Approve? (all / numbers e.g. "1,2,4" / edit N / skip N / apply rewrite N / cancel)
```

**Wait for the user.**

- `all` → apply every proposed write (points and comments) in Step 5; rewrites stay inside the comments as suggestions
- `1,2,4` → apply only those items; the rest are recorded as skipped
- `edit N` → ask what to change on item N (points value, comment text, or rewrite text), revise, re-show that item, ask again
- `apply rewrite N` → write item N's rewrite directly onto the work item in Step 5 (instead of only suggesting it in the comment). This covers the description, the title if the rewrite included one, and rewritten AC **only where the item already had AC** — an empty AC field is never populated, under this or any other option
- `skip N` → drop item N, re-ask for the rest
- `cancel` → stop with **zero changes** to Azure DevOps

## Step 5: Apply Approved Changes

Only for approved items, in batch order:

1. **Set Story Points and move to Dev Ready** (items with a proposed number): in one `mcp__azure-devops__wit_update_work_item` call, set `Microsoft.VSTS.Scheduling.StoryPoints` **and** `System.State` = `Dev Ready`. The state change applies only to `User Story`, `Bug`, and `Hot Fix` types, and never moves an item backward — if an item is somehow already past Dev Ready, set the points only and note it. Touch no other field — assignee, iteration, and tags stay as they are.
2. **Post the comment** (items with an approved draft): add it with `mcp__azure-devops__wit_add_work_item_comment` (or the server's work-item comment tool). Use the mention syntax the server supports so the creator is notified; otherwise lead with their display name as drafted.
3. **Apply the rewrite** (only items the user marked `apply rewrite N`): update `System.Description` (and `System.Title` if the rewrite included one) via `wit_update_work_item`, and adjust the comment to say the rewrite was applied ("rewrote the description/AC per the above — please review") rather than suggesting it. Never apply a rewrite the user didn't explicitly mark.

   **Guard on `Microsoft.VSTS.Common.AcceptanceCriteria`:** write it only if the item's AC field was **non-empty** when fetched in 3a. Re-check the fetched value at write time — if it was blank, drop AC from the update payload and write the other fields. Blank means no criteria at all: empty string, whitespace, or an empty HTML shell like `<div></div>` or `<p><br></p>`.

If a write fails, report the failure and ask whether to continue with the remaining items or stop.

## Step 6: Final Summary

```
## Quote Sweep Complete — {project}

Items analyzed:   {n} (of {total} qualifying — {remaining} left for the next run)
  ✓ Points set:   {n_pointed}  (total {sum} pts — each moved to Dev Ready)
  ✓ Comments:     {n_comments} posted to creators
  ✓ Rewrites:     {n_rewrites_applied} applied, {n_rewrites_suggested} suggested in comments
  ⚑ AC missing:   {n_ac_missing} items sent back to the creator to write their acceptance criteria
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

Do not create tasks or assign items — those are downstream decisions. Pointed items are now Dev Ready, so `/plan-backlog` picks them up on its next run. Make no state change other than the points→Dev Ready move described in Step 5.
