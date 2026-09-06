Promote all code from one environment to the next. Usage: `/promote [source] [target]`

Parse `$ARGUMENTS` to extract:
- **Source**: optional — an environment or branch name (`main`, `dev`, `test`, `staging`). If omitted, auto-detect from the current branch.
- **Target**: optional — the environment to promote into. If omitted, use the next row in the promotion flow.

## Environment ↔ State Reference

Resolve branch names from the project's `CLAUDE.md` **Pipeline Configuration** table — never hardcode them. The first row is the compare branch (`main`; feature PRs target it, **merging into it deploys nothing**); the rows below are the environment branches in promotion order, and a PR merging into one of them is what triggers its pipeline:

| Branch | Environment | Gate — items should already be in… | State set after the PR merges |
|---|---|---|---|
| `main` | — (compare branch) | — | — |
| `dev` | Dev | `Code Review` (merged to `main`) | `Ready for Testing` |
| `test` | Test | `Ready for Testing` | `Testing` |
| `staging` | Staging | `Ready for Staging` | `Staging` |
| `prod` | Production | `Ready to Deploy` | `Deployed` |

`Ready for Staging` and `Ready to Deploy` are set by QA and stakeholders — **never by this command**.

## Step 1: Determine Source and Target

Read the Pipeline Configuration table. If it is missing, fall back to `git branch -r` and ask the user to confirm the pair. If not specified, auto-detect based on the current branch:

| Current Branch | Source | Target |
|---|---|---|
| `main` | main | dev |
| `dev` | dev | test |
| `test` | test | staging |
| `staging` | staging | prod |
| `prod` | — | Nothing above production — report and stop |
| a feature/work branch | — | Ask which pair to promote |

If both are specified (e.g., `/promote staging prod`), use those directly. Accept environment names (`production`, `Dev`) as well as branch names and map them through the table. Refuse to promote **backward** (e.g. `prod → staging`) — that is `/rollback`'s job.

`main → dev` is the usual first hop: it carries every feature PR that has merged into `main` and gives it its first deployment.

## Step 2: Show What Will Be Promoted

```bash
git fetch origin <source-branch> <target-branch>
git log origin/<target-branch>..origin/<source-branch> --oneline
```

Present the changes, resolving work items from `AB#` references in commit messages (or `repo_search_commits` with `includeWorkItems: true`):

```
## Promote {source} → {target}

Commits to promote:
| Commit | Message | Work Item |
|--------|---------|-----------|
| abc1234 | Add payment export | AB#1234 |
| def5678 | Fix login redirect | AB#1235 |
| ghi9012 | Update dashboard | AB#1236 |

{count} commits will be promoted from {source} to {target}.
```

If there are no new commits, report that the environments are already in sync and stop.

## Step 3: Gate Check

Fetch each referenced work item and compare its `System.State` with the target's gate. Promotion carries **everything** on the source branch, so an item behind the gate can't be dropped — the choice is to proceed, or to stop and use `/deploy-release` / `/cherry-pick` for a subset:

```
⚠ Gate check for {target} (expects `{gate state}`):

| ID | State | Note |
|----|-------|------|
| AB#1236 | Testing | behind — QA hasn't marked it Ready for Staging |

/promote carries the whole branch. Options:
  1. Promote anyway (AB#1236 goes to {target} too)
  2. Stop — use /deploy-release or /cherry-pick for just the ready items

Which? (1 / 2)
```

For `main → dev` the gate is `Code Review`: an item still at `Code Review` whose commits are on `main` has had its PR merged, which is exactly right — not a warning. Features and Tasks are skipped. Items *ahead* of the gate are reported and left alone.

Then confirm: `Promote {count} commits from {source} to {target}? (yes/no)` — and wait.

## Step 4: Create PR

Create a PR directly from the source branch to the target branch via Azure DevOps MCP:

- **sourceRefName**: `refs/heads/<source-branch>`
- **targetRefName**: `refs/heads/<target-branch>`
- **title**: `Promote {source} → {target}`
- **description**: List all commits and associated work items being promoted

Link the associated work items to the PR.

## Step 5: Present Summary and Wait for the Merge

```
Promotion PR created: {source} → {target}

PR: {pr-url}

{count} commits, {n} work items included.
Merging the PR triggers the CD pipeline for {target}.

Reply `merged` once the PR is complete and the pipeline is green — I'll move the {n} work items to `{state after merge}`. (Or `skip` to leave the states alone.)
```

Do NOT merge the PR automatically — the user or a reviewer must approve and merge.

## Step 6: Advance Work Item States (after `merged`)

When the user replies `merged`:

1. **Confirm the PR is actually completed** via the Azure DevOps MCP. If it isn't, say so and wait — never advance states for an unmerged PR.
2. For every carried work item of type **User Story**, **Bug**, or **Hot Fix**, set `System.State` to the target's state (`Ready for Testing` / `Testing` / `Staging` / `Deployed`) via `wit_update_work_item`.
   - **Never move backward** — an item already past the target state keeps it; note it.
   - **Never touch a Feature or Task.**
   - An invalid-state error means this project's template differs — confirm with `get_type`, report the item, continue with the rest. Don't silently swallow it.
3. Report a `Was → Now` table per item and the next human step (QA sets `Ready for Staging`; stakeholders set `Ready to Deploy`; verify in production, then `Closed`).

If the user replies `skip`, leave the states alone and note that `/status` will flag the lag later.
