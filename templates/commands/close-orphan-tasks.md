Close orphaned tasks — open Tasks whose parent has already moved to a deploy/done state. Usage: `/close-orphan-tasks [scope] [--dry-run]`

An **orphaned task** here means a child Task that is still open while its parent work item has already reached one of these states:

- `Ready to Deploy`
- `Deployed`
- `Closed`

When a parent is deployed or closed, leftover open child Tasks just add noise to the board. This command finds them and closes them in a single pass.

Parse `$ARGUMENTS`:
- If it contains `dry-run` or `--dry-run`, only list the orphaned tasks — do **not** close anything.
- Any other text is an optional **scope** filter — an Area Path, product prefix (`COM`, `PAY`, …), or iteration to narrow the search. With no scope, search the whole project.

All work items live in the **CSI Development** Azure DevOps project (see CLAUDE.md). Target that project unless the repo's CLAUDE.md says otherwise.

## Step 1: Find Orphaned Tasks

Use the Azure DevOps MCP `wit_query_by_wiql` with a hierarchy link query. The Source is the parent, the Target is the child Task:

```sql
SELECT [System.Id]
FROM WorkItemLinks
WHERE
  ([Source].[System.State] IN ('Ready to Deploy', 'Deployed', 'Closed'))
  AND ([System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward')
  AND ([Target].[System.WorkItemType] = 'Task')
  AND ([Target].[System.State] NOT IN ('Closed', 'Removed', 'Done'))
MODE (MustContain)
```

If a **scope** was given, add the matching constraint to the `[Target]` clause (e.g. `AND [Target].[System.AreaPath] UNDER 'CSI Development\\Compass'`, or `AND [Target].[System.Title] CONTAINS 'PAY'`).

> **Note on state names:** Process templates vary. Some projects close tasks to `Done` instead of `Closed`, or use `Resolved`. If the query returns nothing or errors on an unknown state, first confirm the valid states for the Task type via `wit_get_work_item_type`, then adjust the `NOT IN` list and the close target in Step 3 accordingly.

If the link query is unsupported or returns no usable pairs, fall back to: query all open Tasks in scope with a flat WIQL, fetch each task's parent via `relations`, and keep only those whose parent state is in the three target states.

Fetch the matched tasks (and their parents) in a batch via `wit_get_work_items_batch_by_ids` to get titles, states, assignees, and parent context.

## Step 2: Present the Candidates

```
## Orphaned Tasks ({count})

| Task | Title | State | Parent | Parent State |
|------|-------|-------|--------|--------------|
| AB#4710 | Add export endpoint | Active | AB#4521 | Deployed |
| AB#4711 | Wire up CSV service | New | AB#4521 | Deployed |
| AB#4733 | Fix null check | Active | AB#4598 | Closed |

These tasks will be set to **Closed** with a comment noting the parent's state.

Close {count} orphaned tasks? (yes/no)
```

If `--dry-run`, show the table but do **not** ask for confirmation and do **not** close anything. Stop here.

Otherwise, wait for explicit confirmation before proceeding. Never close tasks without a yes.

## Step 3: Close the Tasks

For each confirmed task, use `wit_update_work_items_batch`:
- **path**: `/fields/System.State`
- **value**: `Closed` (or the project's terminal Task state confirmed in Step 1)

Then add a comment on each via `wit_add_work_item_comment` so the auto-close is traceable:

> Auto-closed by `/close-orphan-tasks` — parent AB#{parentId} is in state "{parentState}".

Do not modify the parent items. Do not touch tasks whose parent is in any other state.

## Step 4: Report

```
Closed {count} orphaned tasks.

| Task | Title | Parent | Parent State |
|------|-------|--------|--------------|
| AB#4710 | Add export endpoint | AB#4521 | Deployed |
| AB#4711 | Wire up CSV service | AB#4521 | Deployed |
| AB#4733 | Fix null check | AB#4598 | Closed |

Skipped: {n} (state transition not permitted — list any that the board rejected)
```

If any update was rejected (e.g. a required field or an invalid state transition), list it under **Skipped** with the reason rather than silently dropping it.
