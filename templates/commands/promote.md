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

## Step 5: Pick Who Verifies Each Group (before the merge)

The items are about to land in {target environment} for **someone** to verify. Decide who now, while the PR is still in review — nothing is written yet; the assignment is applied in Step 7 together with the state change, once the pipeline is green.

### 5a. Group by title prefix

Work item titles in the CSI Development project are `PREFIX - Title` (`COM`, `PAY`, `CDA`, `AUD`, `SER`, `PSSF`, `TPS`, `ILP`, `RBWO`, `MTG`, `CSI`). Group the carried **User Stories, Bugs, and Hot Fixes** by that prefix. Titles with a missing or unrecognized prefix go in a `(no prefix)` group. Features and Tasks are never assigned by this command — leave them out of the grouping.

One question per group. Different products usually have different verifiers, but the same person may take several groups — that is the normal case, not an error.

### 5b. Build each group's candidate list from the items themselves

For every item in the group, collect the distinct identities already on it:

- **whoever set the gate state** — `wit_work_item` `action: list_revisions`, then the `System.ChangedBy` on the revision where `System.State` became the target's gate state (`Ready for Staging`, `Ready to Deploy`, …). That is the QA person or stakeholder who signed the item off, and it is usually the right verifier.
- `System.CreatedBy` — who asked for the work
- comment authors — `wit_work_item` `action: list_comments`
- `System.ChangedBy` — the most recent editor

Then **drop the developers**, so what remains is the non-developer names on the item:

- each item's current `System.AssignedTo` (the dev who implemented it)
- the PR author
- the authors of the promoted commits — `git log origin/<target>..origin/<source> --format='%an <%ae>' | sort -u`

Rank the survivors by how many items in the group they appear on — the gate-state signer first, then creators. **Do not invent names**, do not pull from the org directory or a team list, and do not carry a name over from another group's items — every candidate must come from the items in that group.

If the developer filter empties a group's list, say so and show the unfiltered names marked `(also a developer here)`, plus the option to type a name.

### 5c. Ask

```
## Who verifies on {environment}?

**COM** — 2 items (AB#1234, AB#1236)
  1. Jane Doe (jane@caresolutions.com) — created both
  2. Sam Lee (sam@caresolutions.com) — commented on AB#1234
  3. Someone else — give me a name or email
  4. Leave the current assignee alone

**PAY** — 2 items (AB#1240, AB#1241)
  1. Jane Doe (jane@caresolutions.com) — created AB#1240
  2. Pat Ruiz (pat@caresolutions.com) — commented on both
  3. Someone else
  4. Leave the current assignee alone

Reply per group — `COM 1, PAY 2` — or `all 1` to give every group to the same person.
```

### 5d. Confirm the mapping

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

`change` re-asks 5c. Only after `yes` do you move on — if the PR merges before the user answers, keep waiting for the answer, then run Step 7.

## Step 6: Watch the Merge, Then the Pipeline

Do NOT merge the PR yourself — a reviewer approves and completes it. Report the PR, then watch for the deployment:

```
Promotion PR created: {source} → {target}

PR: {pr-url}

{count} commits, {n} work items included.
Merging the PR triggers the CD pipeline for {target}. I'm watching the PR and
that pipeline — when it comes back green I'll set the {n} work items to
`{state after merge}` and assign them as approved above. Nothing is written
until then. Say `stop watching` to leave the states alone.
```

1. **Wait for the PR to complete.** Poll `repo_pull_request` until `status` is `completed`; note the merge commit and the completion time. `abandoned` → stop, change nothing, report it.
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

## Step 7: Assign and Advance States (automatic, on a green pipeline)

This step runs **by itself** the moment the pipeline reports success — do not ask again; the approval in Step 5d covers it. All three preconditions must hold: the PR is `completed`, **every** CD run for {target} is `succeeded`, and a Step 5d mapping was approved.

- `partiallySucceeded` → not green. Report which stage failed and ask `proceed` / `hold`.
- `failed` / `canceled` → change nothing. Report the run, the failing stage, and the log link (`pipelines_build_log`), and offer `/rollback` if the environment is broken.
- No Step 5d approval yet (user hasn't answered) → do the state changes only when they answer; don't guess an assignee.

For every carried work item of type **User Story**, **Bug**, or **Hot Fix**, one `wit_work_item_write` update per item setting both fields:

1. `System.State` → the target's state (`Ready for Testing` / `Testing` / `Staging` / `Deployed`).
   - **Never move backward** — an item already past the target state keeps it; note it.
   - An invalid-state error means this project's template differs — confirm with `get_type`, report the item, continue with the rest. Don't silently swallow it.
2. `System.AssignedTo` → the person approved for that item's prefix group. Pass the identity's `uniqueName` / email, not the display name; if the update rejects it, resolve with `core_get_identity_ids` and retry once. A `Leave the current assignee alone` group keeps its assignee — never clear a field the user didn't ask you to clear.

**Never touch a Feature or Task** — neither state nor assignee.

Report both fields, so a wrong assignment is easy to put back:

```
{source} → {target} is deployed (pipeline {build-number}, succeeded).

| ID | State: was → now | Assignee: was → now |
|----|------------------|---------------------|
| AB#1234 | Ready for Staging → Staging | Chris Waters → Jane Doe |
| AB#1240 | Ready for Staging → Staging | Chris Waters → Pat Ruiz |
| AB#1250 | Deployed (unchanged — already ahead) | unchanged |

Next: {the human step — "QA tests on Test and sets Ready for Staging" / "stakeholders verify on Staging and set Ready to Deploy" / "verify in production, then Close"}.
```

If the user said `stop watching`, or an update fails, leave the rest alone, say exactly which items were and were not updated, and note that `/status` will flag the lag later.
