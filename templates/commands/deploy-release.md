Deploy release to the next environment. Usage: `/deploy-release <release-number> [environment]`

Parse `$ARGUMENTS` to extract:
- **Release number**: required (e.g., "23" or "#23")
- **Target environment**: optional — an environment name (`dev`, `test`, `staging`, `prod`/`production`) or its branch. If not provided, auto-detect the next environment in the promotion flow.

## Environment ↔ State Reference

Resolve branch names from the project's `CLAUDE.md` **Pipeline Configuration** table — never hardcode them. The first row is the compare branch (`main`; feature PRs target it, **merging into it deploys nothing**); the rows below are the environment branches in promotion order, and a PR merging into one of them is what triggers its pipeline. The standard layout, with the work item state that goes with each environment:

| Branch | Environment | Gate — items should already be in… | State set after the PR merges |
|---|---|---|---|
| `main` | — (compare branch) | — | — |
| `dev` | Dev | `Code Review` (merged to `main`) | `Ready for Testing` |
| `test` | Test | `Ready for Testing` | `Testing` |
| `staging` | Staging | `Ready for Staging` | `Staging` |
| `prod` | Production | `Ready to Deploy` | `Deployed` |

`Ready for Staging` and `Ready to Deploy` are set by QA and stakeholders — **never by this command**. If the project's table has different environments, confirm the type's states with `mcp__azure-devops__wit_work_item` (`action: get_type`) and map them the same way: a "Ready for X" gate → an "in X" state.

## Step 1: Read the Release

Query Azure DevOps for all work items tagged with `release-{N}` or assigned to the `Release #{N}` iteration using `search_workitem` or `wit_get_work_items_for_iteration`.

Present the release contents:

```
## Release #{N} — Deploy to {environment}

| ID | Type | Title | State | Branch |
|----|------|-------|-------|--------|
| AB#1234 | User Story | Add payment export | Ready for Staging | story/AB#1234-add-payment-export |
| AB#1235 | Bug | Fix login redirect | Ready for Staging | bugfix/AB#1235-fix-login-redirect |

{count} work items in this release.
```

If no work items are found, STOP and report the error.

## Step 2: Determine Target Environment

If the user specified an environment, use it. Otherwise auto-detect: find the **furthest** branch in the Pipeline Configuration table that already contains the work items' commits (`repo_search_commits` with `includeWorkItems: true`, or `git merge-base --is-ancestor <commit> origin/<branch>`), and target the **next row down**:

| Work items' commits are on… | Next target |
|---|---|
| `main` only | `dev` |
| `dev` | `test` |
| `test` | `staging` |
| `staging` | `prod` |
| `prod` | Nothing — report that the release is fully deployed and stop |

**Validation:** Verify all work items in the release have commits on the same source branch. If they are inconsistent (e.g., AB#1234 is on `test` but AB#1235 has nothing past `main`), present a warning listing which work items are on which branches and ask the user to confirm the target environment explicitly.

## Step 3: Gate Check

Compare each work item's `System.State` with the gate for the target environment. Sort into three buckets:

- **At the gate** — proceed silently.
- **Behind the gate** (e.g. still `Testing` when the target is `staging`, or `Active` when the target is `test`) — QA or a stakeholder hasn't signed off yet.
- **Ahead of the gate** (e.g. already `Deployed`, or `Staging` when the target is `test`) — it has already been through this environment; a redeploy is usually harmless but worth knowing.

Features and Tasks aren't carried by state — list them and skip the check. If anything is behind or ahead, show it before asking to proceed:

```
⚠ Gate check for {environment} (expects `{gate state}`):

| ID | State | Note |
|----|-------|------|
| AB#1236 | Testing | behind — QA hasn't marked it Ready for Staging |
| AB#1240 | Deployed | ahead — already in production |

Include them anyway, or drop them from this deploy? (include / drop / cancel)
```

Wait for the answer. `drop` removes them from **this deploy only** — they stay in the release.

## Step 4: Confirm

```
Deploy Release #{N} ({count} work items) to {environment}?

This will:
1. Create a release branch: release/{N}-to-{environment}
2. Cherry-pick all commits for the {count} work items
3. Create a PR targeting `{target-branch}` — merging it triggers the {environment} pipeline
4. After you confirm the merge, move the work items to `{state after merge}`

Proceed? (yes/no)
```

Wait for confirmation.

## Step 5: Create Release Branch

```bash
# Switch to the target environment branch and pull latest
git checkout <target-environment-branch>
git pull origin <target-environment-branch>

# Create the release branch
git checkout -b release/{N}-to-<environment>
```

## Step 6: Cherry-Pick Work Item Commits

For each work item in the release:

1. Find the associated commits using `repo_search_commits` with `includeWorkItems: true`, or by searching for `AB#{id}` in commit messages
2. Cherry-pick each commit in chronological order:
   ```bash
   git cherry-pick <commit-hash>
   ```
3. If conflicts arise, STOP and report them. Do not resolve automatically. Present recovery options:

```
CONFLICT while cherry-picking AB#1236 (commit ghi9012)

Conflicting files:
- src/API/Controllers/HistoryController.cs

Options:
1. Skip this work item and continue with the rest
2. Abort the entire release deploy and clean up
3. I will resolve the conflict manually — wait for me

Which option? (1 / 2 / 3)
```

- **Option 1:** Run `git cherry-pick --skip` and continue. Note the skipped item in the summary — it does **not** get its state advanced in Step 9.
- **Option 2:** Run `git cherry-pick --abort`, delete the release branch, switch back. Report which items were NOT deployed.
- **Option 3:** Wait for the user to resolve and run `git cherry-pick --continue`, then proceed.

Track progress as you go:

```
Cherry-picking commits for Release #{N}:
[x] AB#1234: Add payment export (3 commits)
[x] AB#1235: Fix login redirect (1 commit)
[ ] AB#1236: View history (2 commits) — CONFLICT
```

## Step 7: Push and Create PR

1. Push the release branch: `git push -u origin HEAD`
2. Create a PR via Azure DevOps MCP:
   - **sourceRefName**: `refs/heads/release/{N}-to-<environment>`
   - **targetRefName**: `refs/heads/<target-environment-branch>`
   - **title**: `Release #{N} → {Environment}`
   - **description**: List all work items included with their IDs and titles
3. Link all work items to the PR via `wit_link_work_item_to_pull_request`

## Step 8: Present Summary and Wait for the Merge

```
Release #{N} PR created for {environment}.

PR: {pr-url}
Branch: release/{N}-to-{environment} → {target-branch}

Work items included:
- AB#1234: Add payment export
- AB#1235: Fix login redirect
- AB#1236: View history

Next steps:
- Review and approve the PR
- Merging it triggers the CD pipeline for {environment}
- Reply `merged` once the PR is complete and the pipeline is green — I'll move these {count} work items to `{state after merge}`. (Or `skip` to leave the states alone.)
```

Do NOT trigger the CD pipeline — it triggers automatically on PR merge. Do NOT merge the PR yourself.

## Step 9: Advance Work Item States (after `merged`)

When the user replies `merged`:

1. **Confirm the PR is actually completed** via the Azure DevOps MCP (`status: completed`). If it isn't, say so and wait — never advance states for an unmerged PR.
2. For every carried work item of type **User Story**, **Bug**, or **Hot Fix**, set `System.State` to the target environment's state (`Ready for Testing` / `Testing` / `Staging` / `Deployed`) via `wit_update_work_item` (or the batch variant).
   - **Never move backward.** An item already past the target state (e.g. `Deployed` when deploying to `staging`) keeps its state; note it.
   - **Never touch a Feature or Task.** Features advance as their stories do; Tasks were closed at PR creation.
   - Items skipped in Step 6 (conflict) or dropped in Step 3 are not on the branch — leave them alone.
   - An invalid-state error means this project's template differs — confirm with `get_type`, report the item, continue with the rest. Don't silently swallow it.
3. Report:

```
Release #{N} is on {environment}.

| ID | Was | Now |
|----|-----|-----|
| AB#1234 | Ready for Staging | Staging |
| AB#1235 | Ready for Staging | Staging |
| AB#1240 | Deployed | Deployed (unchanged — already ahead) |

Next: {the human step — "QA tests on Test and sets Ready for Staging" / "stakeholders verify on Staging and set Ready to Deploy" / "verify in production, then Close"}.
```

If the user replies `skip`, leave the states alone and note that `/status release {N}` will flag the lag later.

## Step 10: Notify Team (if Teams MCP is configured)

Send a notification to the project's Teams channel via the Microsoft Teams MCP server:

```
🚀 Release #{N} PR created for {environment}
PR: {pr-url}
Work items: AB#1234, AB#1235, AB#1236
Awaiting review and merge.
```

If the Teams MCP server is not configured, skip this step silently.
