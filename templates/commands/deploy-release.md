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
4. Ask who verifies each product group on {environment} (before the merge)
5. Watch the pipeline — once it's green, set the work items to `{state after merge}` and assign them to the approved verifiers

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

- **Option 1:** Run `git cherry-pick --skip` and continue. Note the skipped item in the summary — it does **not** get its state advanced or its assignee changed in Step 10.
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

## Step 8: Pick Who Verifies Each Group (before the merge)

The release is about to land in {environment} for **someone** to verify. Decide who now, while the PR is still in review — nothing is written yet; the assignment is applied in Step 10 together with the state change, once the pipeline is green.

### 8a. Group by title prefix

Work item titles in the CSI Development project are `PREFIX - Title` (`COM`, `PAY`, `CDA`, `AUD`, `SER`, `PSSF`, `TPS`, `ILP`, `RBWO`, `MTG`, `CSI`). Group the deployed **User Stories, Bugs, and Hot Fixes** by that prefix. Titles with a missing or unrecognized prefix go in a `(no prefix)` group. Items skipped on a conflict (Step 6) or dropped at the gate (Step 3) are not on the branch — leave them out. Features and Tasks are never assigned by this command.

A release that spans products lands in several groups — one question each. Different products usually have different verifiers, but the same person may take several groups; that is the normal case, not an error.

### 8b. Build each group's candidate list from the items themselves

For every item in the group, collect the distinct identities already on it:

- **whoever set the gate state** — `wit_work_item` `action: list_revisions`, then the `System.ChangedBy` on the revision where `System.State` became the target's gate state (`Ready for Staging`, `Ready to Deploy`, …). That is the QA person or stakeholder who signed the item off, and it is usually the right verifier.
- `System.CreatedBy` — who asked for the work
- comment authors — `wit_work_item` `action: list_comments`
- `System.ChangedBy` — the most recent editor

Then **drop the developers**, so what remains is the non-developer names on the item:

- each item's current `System.AssignedTo` (the dev who implemented it)
- the PR author
- the authors of the release commits — `git log --format='%an <%ae>' <target-branch>..HEAD | sort -u`

Rank the survivors by how many items in the group they appear on — the gate-state signer first, then creators. **Do not invent names**, do not pull from the org directory or a team list, and do not carry a name over from another group's items — every candidate must come from the items in that group.

If the developer filter empties a group's list, say so and show the unfiltered names marked `(also a developer here)`, plus the option to type a name.

### 8c. Ask

```
## Who verifies Release #{N} on {environment}?

**COM** — 2 items (AB#1234, AB#1236)
  1. Jane Doe (jane@caresolutions.com) — set Ready to Deploy on both
  2. Sam Lee (sam@caresolutions.com) — commented on AB#1234
  3. Someone else — give me a name or email
  4. Leave the current assignee alone

**PAY** — 2 items (AB#1240, AB#1241)
  1. Pat Ruiz (pat@caresolutions.com) — created both
  2. Jane Doe (jane@caresolutions.com) — commented on AB#1240
  3. Someone else
  4. Leave the current assignee alone

Reply per group — `COM 1, PAY 1` — or `all 1` to give the whole release to one person.
```

### 8d. Confirm the mapping

Echo the resolved plan and wait for an explicit `yes`:

```
When the {environment} pipeline goes green I will apply:

| ID | Title | Prefix | Assign to | State |
|----|-------|--------|-----------|-------|
| AB#1234 | COM - Add payment export | COM | Jane Doe | Staging |
| AB#1236 | COM - View history | COM | Jane Doe | Staging |
| AB#1240 | PAY - Fix login redirect | PAY | Pat Ruiz | Staging |

Approve? (yes / change)
```

`change` re-asks 8c. Only after `yes` do you move on — if the PR merges before the user answers, keep waiting for the answer, then run Step 10.

## Step 9: Get the PR Merged, Then Watch the Pipeline

Never trigger the CD pipeline by hand — it triggers on the merge.

### 9a. Who completes the PR depends on the target

| Target | Who merges |
|---|---|
| `dev`, `test`, `staging` | **You do** — poll until Serena approves, then complete the PR (9b–9c) |
| `prod` | A human. **Never auto-merge into production.** |

Resolve the target through the Pipeline Configuration table, not by the spelling of the branch — a project whose staging branch is named `Staging` or `release/staging` is still staging, and a project with no `test` row simply has no test hop.

Report the PR either way:

```
Release #{N} PR created for {environment}.

PR: {pr-url}
Branch: release/{N}-to-{environment} → {target-branch}

Work items included:
- AB#1234: COM - Add payment export
- AB#1236: COM - View history
- AB#1240: PAY - Fix login redirect

{merge line}
```

`{merge line}` for `dev` / `test` / `staging`:

```
Waiting on Serena's review. When she approves I'll complete the PR, which
triggers the {environment} CD pipeline; when that comes back green I'll set
these {count} items to `{state after merge}` and assign them as approved
above. Say `don't merge` to stop before the merge, or `stop watching` to
leave the work item states alone.
```

`{merge line}` for `prod`:

```
Review and approve the PR — a person merges this one; I don't merge into
production. Merging it triggers the CD pipeline for {environment}. I'm
watching the PR and that pipeline; when it comes back green I'll set these
{count} items to `{state after merge}` and assign them as approved above.
Nothing is written until then. Say `stop watching` to leave the states alone.
```

### 9b. Wait for Serena's approval (`dev` / `test` / `staging` only)

Serena is the AI reviewer on this org's pull requests. Find her among the PR's reviewers by matching `serena` case-insensitively against `displayName` / `uniqueName` — never hardcode an identity id, and never count another reviewer's approval as hers.

Reviewer votes: `10` approved · `5` approved with suggestions · `0` no vote yet · `-5` waiting for author · `-10` rejected.

- `10` or `5` → approved. Go to 9c.
- `-5` or `-10` → **do not merge.** List her threads (`repo_pull_request_thread` `action: list`), report what she flagged, and stop. A release branch is a cherry-pick of commits that already merged upstream, so the fix usually belongs on the source branch and comes forward in the next release — not as a patch commit on `release/{N}-to-{environment}`.
- `0`, or she is not on the reviewer list yet → keep polling.

**Never cast a vote on the PR yourself** to satisfy an approval policy, and never add yourself as a reviewer to do it.

Poll in the background — never a foreground `sleep`:

```bash
ORG=<org-url>; PR=<pr-id>; TRIES=0
while [ $TRIES -lt 120 ]; do
  VOTE=$(az repos pr show --id "$PR" --org "$ORG" \
           --query "reviewers[].[displayName,vote]" -o tsv \
         | grep -i serena | cut -f2 | head -1)
  case "$VOTE" in
    10|5)   echo "APPROVED vote=$VOTE"; break ;;
    -5|-10) echo "BLOCKED  vote=$VOTE"; break ;;
    *)      TRIES=$((TRIES + 1)); sleep 30 ;;
  esac
done
[ $TRIES -ge 120 ] && echo "TIMEOUT - no Serena vote after 60 minutes"
```

Run it with `Monitor` (or Bash `run_in_background`). An empty `VOTE` means she isn't a reviewer yet, which is why the loop keeps going rather than treating it as a decision. Without the Azure CLI, poll `repo_pull_request` `action: get` on the same ~30-second cadence and read `reviewers[]`.

If the loop times out, leave the PR open and ask whether to keep waiting or merge without her. **If she was never added as a reviewer at all, say exactly that** — it usually means the PR was never picked up for review, not that it sailed through.

### 9c. Complete the PR

Merge with `repo_pull_request_write` `action: update`:

| Field | Value | Why |
|---|---|---|
| `autoComplete` | `true` | ADO completes it the moment the remaining branch policies pass — a required build still gates the merge |
| `mergeStrategy` | `NoFastForward` | one merge commit, cherry-pick history intact |
| `transitionWorkItems` | `false` | **required.** This command owns the work item states (Step 10); ADO's own transition moves parents too |
| `deleteSourceBranch` | `true` | the `release/{N}-to-{environment}` branch is disposable — the release itself lives in the iteration and the `release-{N}` tags |
| `bypassPolicy` | **never set it** | a policy that isn't passing is a stop, not an obstacle |

Then poll `repo_pull_request` `action: get` until `status` is `completed`. If it stays `Active` with autocomplete queued, a branch policy is unmet — report which one and stop; do not bypass it and do not push to the source branch to force it.

CLI fallback if the MCP update fails:

```bash
az repos pr update --id <pr-id> --org <org-url> \
  --auto-complete true --transition-work-items false --delete-source-branch true \
  --merge-commit-message "Release #{N} -> {Environment}"
```

If the user said `don't merge`, leave the PR open, say so, and skip to 9d — a human merging it later still gets the pipeline watch and the state changes.

### 9d. Watch the CD pipeline

1. **Confirm the PR completed.** Poll `repo_pull_request` until `status` is `completed`; note the merge commit and completion time. `abandoned` → stop, change nothing, report it.
2. **Find the CD run.** Look up the target branch's pipeline ID(s) in the Pipeline Configuration table, then poll `pipelines_build` for runs on `refs/heads/<target-branch>` queued at or after the merge time — match the merge commit when the run exposes it — and **capture each run's id**. A run that was already completed before the merge is not this deployment; ignore it. A branch with more than one pipeline (API + Client) must have **all** of them green.
3. **Wait for a terminal result** on each run: `succeeded`, `partiallySucceeded`, `failed`, or `canceled`.

**How to wait.** Never block on a foreground `sleep`. If the Azure CLI with the `azure-devops` extension is available, arm a background watch that notifies you on a terminal state:

```bash
# <run-id> is the run identified in step 2 — never "the latest run on the branch",
# which can be a run queued before the merge and already completed.
until az pipelines runs show --org <org-url> --project <project> \
        --id <run-id> --query status -o tsv | grep -qx completed; do
  sleep 60
done
az pipelines runs show --org <org-url> --project <project> \
  --id <run-id> --query "[buildNumber,status,result]" -o tsv
```

Run it with `Monitor` (or Bash `run_in_background`) so the session stays usable. Watch the **run id**, and print `result` when it exits — a guard that only greps for success is silent through a failed or canceled deploy, which looks identical to one still running. One watch per pipeline when the branch has more than one.

Without the CLI, re-poll through the Azure DevOps MCP on roughly a 60-second cadence and report progress as you go. If the deploy outlasts the session's attention, say where it stands and that `check` will re-poll immediately — never claim a pipeline succeeded that you have not seen succeed.

## Step 10: Assign and Advance States (automatic, on a green pipeline)

This step runs **by itself** the moment the pipeline reports success — do not ask again; the approval in Step 8d covers it. All three preconditions must hold: the PR is `completed`, **every** CD run for {environment} is `succeeded`, and a Step 8d mapping was approved.

- `partiallySucceeded` → not green. Report which stage failed and ask `proceed` / `hold`.
- `failed` / `canceled` → change nothing. Report the run, the failing stage, and the log link (`pipelines_build_log`), and offer `/rollback` if the environment is broken.
- No Step 8d approval yet (user hasn't answered) → do the state changes only when they answer; don't guess an assignee.

For every carried work item of type **User Story**, **Bug**, or **Hot Fix**, one `wit_work_item_write` update per item (or the batch variant) setting both fields:

1. `System.State` → the target environment's state (`Ready for Testing` / `Testing` / `Staging` / `Deployed`).
   - **Never move backward.** An item already past the target state (e.g. `Deployed` when deploying to `staging`) keeps its state; note it.
   - Items skipped in Step 6 (conflict) or dropped in Step 3 are not on the branch — leave them alone.
   - An invalid-state error means this project's template differs — confirm with `get_type`, report the item, continue with the rest. Don't silently swallow it.
2. `System.AssignedTo` → the person approved for that item's prefix group. Pass the identity's `uniqueName` / email, not the display name; if the update rejects it, resolve with `core_get_identity_ids` and retry once. A `Leave the current assignee alone` group keeps its assignee — never clear a field the user didn't ask you to clear.

**Never touch a Feature or Task** — neither state nor assignee. Features advance as their stories do; Tasks were closed at PR creation.

Report both fields, so a wrong assignment is easy to put back:

```
Release #{N} is on {environment} (pipeline {build-number}, succeeded).

| ID | State: was → now | Assignee: was → now |
|----|------------------|---------------------|
| AB#1234 | Ready for Staging → Staging | Chris Waters → Jane Doe |
| AB#1236 | Ready for Staging → Staging | Chris Waters → Jane Doe |
| AB#1240 | Ready for Staging → Staging | Chris Waters → Pat Ruiz |
| AB#1250 | Deployed (unchanged — already ahead) | unchanged |

Next: {the human step — "QA tests on Test and sets Ready for Staging" / "stakeholders verify on Staging and set Ready to Deploy" / "verify in production, then Close"}.
```

If the user said `stop watching`, or an update fails, leave the rest alone, say exactly which items were and were not updated, and note that `/track release {N}` will flag the lag later.

## Step 11: Notify Team (if Teams MCP is configured)

Send a notification to the project's Teams channel via the Microsoft Teams MCP server — once when the PR is created:

```
🚀 Release #{N} PR created for {environment}
PR: {pr-url}
Work items: AB#1234, AB#1236, AB#1240
Awaiting review and merge.
```

…and once when Step 10 completes, so the verifiers know it's their turn:

```
✅ Release #{N} deployed to {environment}
COM (AB#1234, AB#1236) → Jane Doe
PAY (AB#1240) → Pat Ruiz
Items are now `{state}` — please verify.
```

If the Teams MCP server is not configured, skip this step silently.
