Cherry-pick specific work items to an environment. Usage: `/cherry-pick <work-item-ids> <environment>`

Parse `$ARGUMENTS` to extract:
- **Work item IDs**: one or more IDs (e.g., "AB#1234 AB#1235" or "1234, 1235")
- **Target environment**: the environment to deploy to (`dev`, `test`, `staging`, `prod`/`production`) or its branch. `main` is also a valid target — that is how a hot fix that went straight to `prod` gets brought back into the compare branch.

## Environment ↔ State Reference

Resolve branch names from the project's `CLAUDE.md` **Pipeline Configuration** table — never hardcode them. The first row is the compare branch (`main`; **merging into it deploys nothing**); the rows below are the environment branches in promotion order, and a PR merging into one of them triggers its pipeline:

| Branch | Environment | Gate — items should already be in… | State set after the PR merges |
|---|---|---|---|
| `main` | — (compare branch) | — | *(no change)* |
| `dev` | Dev | `Code Review` (merged to `main`) | `Ready for Testing` |
| `test` | Test | `Ready for Testing` | `Testing` |
| `staging` | Staging | `Ready for Staging` | `Staging` |
| `prod` | Production | `Ready to Deploy` | `Deployed` |

`Ready for Staging` and `Ready to Deploy` are set by QA and stakeholders — **never by this command**.

## Step 1: Read the Work Items and Gate-Check Them

Fetch each work item from Azure DevOps via MCP. Compare each one's `System.State` with the target's gate and annotate anything behind it (QA or a stakeholder hasn't signed off) or ahead of it (already been through this environment). Features and Tasks are listed but not gate-checked.

```
## Cherry-Pick to {environment}

| ID | Type | Title | State | Gate ({gate state}) |
|----|------|-------|-------|---------------------|
| AB#1234 | User Story | Add payment export | Ready to Deploy | ✓ |
| AB#1235 | Bug | Fix login redirect | Staging | ⚠ behind — stakeholders haven't set Ready to Deploy |

Cherry-pick {count} work items to {environment}? Items behind the gate: include / drop / cancel
```

Wait for confirmation. `drop` removes flagged items from this cherry-pick only.

## Step 2: Find Commits

For each work item, find associated commits using `repo_search_commits` with `includeWorkItems: true`, or by searching for `AB#{id}` in commit messages on the source branch (the environment one step before the target — e.g. `staging` when targeting `prod`, `main` when targeting `dev`).

If no commits are found for a work item, STOP and report which work item has no associated commits.

## Step 3: Create Cherry-Pick Branch

```bash
git checkout <target-environment-branch>
git pull origin <target-environment-branch>
git checkout -b cherry-pick/<date>-to-<environment>
```

## Step 4: Cherry-Pick Commits

Cherry-pick commits for each work item in chronological order:

```bash
git cherry-pick <commit-hash>
```

If conflicts arise, STOP and report them. Do not resolve automatically. Present recovery options:

```
CONFLICT while cherry-picking AB#1235 (commit def5678)

Conflicting files:
- src/API/Controllers/PaymentController.cs

Options:
1. Skip this work item and continue with the rest
2. Abort the entire cherry-pick and clean up
3. I will resolve the conflict manually — wait for me

Which option? (1 / 2 / 3)
```

- **Option 1:** Run `git cherry-pick --skip` and continue with remaining work items. Note the skipped item in the summary — it does **not** get its state advanced in Step 7.
- **Option 2:** Run `git cherry-pick --abort`, delete the cherry-pick branch, and switch back to the original branch.
- **Option 3:** Wait for the user to resolve conflicts and run `git cherry-pick --continue`, then proceed.

Track progress:
```
Cherry-picking:
[x] AB#1234: Add payment export (2 commits)
[ ] AB#1235: Fix login redirect (1 commit) — CONFLICT
```

## Step 5: Push and Create PR

1. Push: `git push -u origin HEAD`
2. Create a PR via Azure DevOps MCP:
   - **sourceRefName**: `refs/heads/cherry-pick/<date>-to-<environment>`
   - **targetRefName**: `refs/heads/<target-environment-branch>`
   - **title**: `Cherry-pick AB#1234, AB#1235 → {Environment}`
   - **description**: List all work items with IDs and titles
3. Link all work items to the PR via `wit_link_work_item_to_pull_request`

## Step 6: Present Summary and Wait for the Merge

```
Cherry-pick PR created for {environment}.

PR: {pr-url}
Work items:
- AB#1234: Add payment export
- AB#1235: Fix login redirect

Merging the PR triggers the CD pipeline for {environment}.
Reply `merged` once the PR is complete and the pipeline is green — I'll move these {count} work items to `{state after merge}`. (Or `skip`.)
```

When the target is `main`, there is no pipeline and no state change — say so and stop here.

## Step 7: Advance Work Item States (after `merged`)

When the user replies `merged`:

1. **Confirm the PR is actually completed** via the Azure DevOps MCP. If it isn't, say so and wait.
2. For every cherry-picked work item of type **User Story**, **Bug**, or **Hot Fix**, set `System.State` to the target's state (`Ready for Testing` / `Testing` / `Staging` / `Deployed`) via `wit_update_work_item`.
   - **Never move backward** — an item already past the target state keeps it; note it.
   - **Never touch a Feature or Task.**
   - Skipped (conflict) or dropped items are not on the branch — leave them alone.
   - An invalid-state error means this project's template differs — confirm with `get_type`, report the item, continue. Don't silently swallow it.
3. Report a `Was → Now` table per item and the next human step.

If the user replies `skip`, leave the states alone and note that `/status` will flag the lag later.
