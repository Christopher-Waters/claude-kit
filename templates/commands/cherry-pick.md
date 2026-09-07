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

- **Option 1:** Run `git cherry-pick --skip` and continue with remaining work items. Note the skipped item in the summary — it does **not** get its state advanced or its assignee changed in Step 8.
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

## Step 6: Pick Who Verifies Each Group (before the merge)

When the target is `main` there is no pipeline, no state change, and **no assignment** — say so and skip to Step 8's summary.

Otherwise the items are about to land in {environment} for **someone** to verify. Decide who now, while the PR is still in review — nothing is written yet; the assignment is applied in Step 8 together with the state change, once the pipeline is green.

### 6a. Group by title prefix

Work item titles in the CSI Development project are `PREFIX - Title` (`COM`, `PAY`, `CDA`, `AUD`, `SER`, `PSSF`, `TPS`, `ILP`, `RBWO`, `MTG`, `CSI`). Group the cherry-picked **User Stories, Bugs, and Hot Fixes** by that prefix. Titles with a missing or unrecognized prefix go in a `(no prefix)` group. Items skipped on a conflict (Step 4) or dropped at the gate (Step 1) are not on the branch — leave them out. Features and Tasks are never assigned by this command.

One question per group. Different products usually have different verifiers, but the same person may take several groups — that is the normal case, not an error.

### 6b. Build each group's candidate list from the items themselves

For every item in the group, collect the distinct identities already on it:

- **whoever set the gate state** — `wit_work_item` `action: list_revisions`, then the `System.ChangedBy` on the revision where `System.State` became the target's gate state (`Ready for Staging`, `Ready to Deploy`, …). That is the QA person or stakeholder who signed the item off, and it is usually the right verifier.
- `System.CreatedBy` — who asked for the work
- comment authors — `wit_work_item` `action: list_comments`
- `System.ChangedBy` — the most recent editor

Then **drop the developers**, so what remains is the non-developer names on the item:

- each item's current `System.AssignedTo` (the dev who implemented it)
- the PR author
- the authors of the cherry-picked commits — `git log --format='%an <%ae>' <target-branch>..HEAD | sort -u`

Rank the survivors by how many items in the group they appear on — the gate-state signer first, then creators. **Do not invent names**, do not pull from the org directory or a team list, and do not carry a name over from another group's items — every candidate must come from the items in that group.

If the developer filter empties a group's list, say so and show the unfiltered names marked `(also a developer here)`, plus the option to type a name.

### 6c. Ask

```
## Who verifies on {environment}?

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

Reply per group — `COM 1, PAY 1` — or `all 1` to give every group to the same person.
```

### 6d. Confirm the mapping

Echo the resolved plan and wait for an explicit `yes`:

```
When the {environment} pipeline goes green I will apply:

| ID | Title | Prefix | Assign to | State |
|----|-------|--------|-----------|-------|
| AB#1234 | COM - Add payment export | COM | Jane Doe | Deployed |
| AB#1240 | PAY - Fix login redirect | PAY | Pat Ruiz | Deployed |

Approve? (yes / change)
```

`change` re-asks 6c. Only after `yes` do you move on — if the PR merges before the user answers, keep waiting for the answer, then run Step 8.

## Step 7: Watch the Merge, Then the Pipeline

Do NOT merge the PR yourself — a reviewer approves and completes it. Report the PR, then watch for the deployment:

```
Cherry-pick PR created for {environment}.

PR: {pr-url}
Work items:
- AB#1234: COM - Add payment export
- AB#1240: PAY - Fix login redirect

Merging the PR triggers the CD pipeline for {environment}. I'm watching the PR
and that pipeline — when it comes back green I'll set these {count} items to
`{state after merge}` and assign them as approved above. Nothing is written
until then. Say `stop watching` to leave the states alone.
```

1. **Wait for the PR to complete.** Poll `repo_pull_request` until `status` is `completed`; note the merge commit and completion time. `abandoned` → stop, change nothing, report it.
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

## Step 8: Assign and Advance States (automatic, on a green pipeline)

This step runs **by itself** the moment the pipeline reports success — do not ask again; the approval in Step 6d covers it. All three preconditions must hold: the PR is `completed`, **every** CD run for {environment} is `succeeded`, and a Step 6d mapping was approved.

- `partiallySucceeded` → not green. Report which stage failed and ask `proceed` / `hold`.
- `failed` / `canceled` → change nothing. Report the run, the failing stage, and the log link (`pipelines_build_log`), and offer `/rollback` if the environment is broken.
- No Step 6d approval yet (user hasn't answered) → do the state changes only when they answer; don't guess an assignee.

For every cherry-picked work item of type **User Story**, **Bug**, or **Hot Fix**, one `wit_work_item_write` update per item setting both fields:

1. `System.State` → the target's state (`Ready for Testing` / `Testing` / `Staging` / `Deployed`).
   - **Never move backward** — an item already past the target state keeps it; note it.
   - Skipped (conflict) or dropped items are not on the branch — leave them alone.
   - An invalid-state error means this project's template differs — confirm with `get_type`, report the item, continue. Don't silently swallow it.
2. `System.AssignedTo` → the person approved for that item's prefix group. Pass the identity's `uniqueName` / email, not the display name; if the update rejects it, resolve with `core_get_identity_ids` and retry once. A `Leave the current assignee alone` group keeps its assignee — never clear a field the user didn't ask you to clear.

**Never touch a Feature or Task** — neither state nor assignee.

Report both fields, so a wrong assignment is easy to put back:

```
Cherry-pick is deployed to {environment} (pipeline {build-number}, succeeded).

| ID | State: was → now | Assignee: was → now |
|----|------------------|---------------------|
| AB#1234 | Ready to Deploy → Deployed | Chris Waters → Jane Doe |
| AB#1240 | Ready to Deploy → Deployed | Chris Waters → Pat Ruiz |
| AB#1250 | Deployed (unchanged — already ahead) | unchanged |

Next: {the human step — "QA tests on Test and sets Ready for Staging" / "stakeholders verify on Staging and set Ready to Deploy" / "verify in production, then Close"}.
```

If the user said `stop watching`, or an update fails, leave the rest alone, say exactly which items were and were not updated, and note that `/status` will flag the lag later.
