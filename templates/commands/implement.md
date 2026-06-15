Implement work item AB#$ARGUMENTS. Follow this workflow:

## Step 1: Read the Work Item

Read the work item from Azure DevOps via MCP. Extract:
- **System.WorkItemType** — determines branch prefix
- **System.Title** — determines branch suffix
- **Acceptance criteria / description** — needed for implementation

Handle `$ARGUMENTS` as either `1234` or `AB#1234` — strip the `AB#` prefix when calling the MCP API.

### Embedded Images

The description and acceptance criteria fields may contain embedded images (screenshots, mockups, diagrams). These are typically `<img>` tags with `src` URLs pointing to Azure DevOps attachments. **Download and view every embedded image** using WebFetch — they often contain critical visual requirements (UI layouts, expected behavior, error states) that are not described in the text.

### Comments

Read the work item comments via `wit_list_work_item_comments`. Comments often contain clarifications, scope changes, or additional requirements added after the work item was created. Incorporate any relevant information from comments into your understanding of the work item.

## Step 2: Summarize and Confirm

Present a summary of the work item to the user:

```
## AB#{id}: {title}

**Type:** {work item type}
**State:** {state}
**Assigned To:** {assigned to}

### Description
{description summary}

### Acceptance Criteria
{acceptance criteria — numbered list}

Does this look correct? Do you have any additional context or requirements?
```

**Wait for the user to respond.** Do NOT proceed until the user confirms or provides additional context. If they add context, incorporate it into the plan.

## Step 3: Explore & Plan

1. **Explore** the codebase to map relevant files
2. **Plan** the implementation approach

Present the plan to the user:

```
## Implementation Plan for AB#{id}

### Approach
{brief description of how you will implement this}

### Files to Create
- `path/to/new/file.cs` — {purpose}
- `path/to/new/file.tsx` — {purpose}

### Files to Modify
- `path/to/existing/file.cs` — {what changes and why}
- `path/to/existing/file.tsx` — {what changes and why}

### Files to Delete (if any)
- `path/to/old/file.cs` — {why it's being removed}

### Unit Tests
- `path/to/new.tests.cs` — covers {scenario 1}, {scenario 2}, {edge case}
- `path/to/existing.tests.cs` — adds cases for {new behavior}

List every test file you will add or modify and the scenarios each covers (happy path, error paths, edge cases, regression guards). If a change in this plan has no test coverage, justify why here.

### Agents
- **backend**: {what it will do}
- **frontend**: {what it will do}

### Risks / Considerations
- {any potential issues or trade-offs}

Approve this plan? (yes / no / suggest changes)
```

**Wait for the user to approve the plan.** Do NOT start implementation until the user approves. If they suggest changes, revise the plan and present it again.

## Step 4: Create Feature Branch

Only create the branch after the plan is approved.

Capture the current branch as the PR target — do NOT hardcode any branch name:

```bash
BASE_BRANCH=$(git symbolic-ref --short HEAD)
```

Determine the branch prefix from the work item type:

| Work Item Type | Branch Prefix |
|---|---|
| Feature | `feature/` |
| User Story | `story/` |
| Bug | `bugfix/` |
| Hot Fix | `hotfix/` |
| (anything else) | `work/` |

Construct the branch name as `{prefix}AB#{id}-{sanitized-title}`:
- Sanitize the title: lowercase, replace non-alphanumeric characters (except hyphens) with hyphens, collapse consecutive hyphens, truncate to 50 characters, trim leading/trailing hyphens
- Example: Feature AB#1234 "Add Payment History Export" → `feature/AB#1234-add-payment-history-export`

Create and switch to the branch:
```bash
git checkout -b <branch-name>
```

If the branch already exists, switch to it with `git checkout <branch-name>` instead of failing.

Remember the `BASE_BRANCH` — you will need it for the PR step.

## Step 5: Implement

1. **Implement** using backend and/or frontend agents according to the approved plan
2. **Write the unit tests** listed in the plan's "Unit Tests" section alongside the implementation — not after
3. **Generate mockup** if there are UI changes

## Step 6: Build Validation

Run a build check **before** any other quality checks. Use the `build-validator` agent to verify that all projects compile successfully.

- If the build fails, **fix the errors immediately** and re-run until the build passes
- Do NOT proceed to review, tests, or lint until the build is clean

## Step 7: Quality Checks

1. **Run the full test suite** — every unit test in the repo, plus integration tests. Not just the tests added in this change. A failure in an unrelated test means this change broke something else; treat it as a regression, fix it, and re-run until the entire suite is green
2. **Run lint** — ESLint and dotnet format

## Step 8: Code Review

Spawn the `reviewer` agent to review the diff for quality, security, Clean Architecture compliance, and CLAUDE.md adherence. The agent is read-only — it reports findings, you act on them.

Present the findings to the user grouped by severity:

```
## Code Review Findings

### Must-fix (blocking)
- {file:line} — {issue + why it blocks}

### Should-fix (recommended)
- {file:line} — {issue + suggested change}

### Nits (optional)
- {file:line} — {minor note}

Address must-fix items? (yes / select / skip)
```

- `yes` → fix every must-fix item, then re-run the reviewer agent on the updated diff
- `select` → ask which items to address; fix only those, then re-run the reviewer agent
- `skip` → proceed without fixes (only allowed if there are no must-fix items, or the user explicitly overrides)

Loop until the reviewer reports no must-fix items, or the user explicitly accepts remaining findings. Do not proceed to UAT with unresolved must-fix items unless the user overrides.

## Step 9: UAT Gate

### If Hot Fix:
Skip manual UAT. Present an abbreviated confirmation:

```
Hot Fix ready. All automated checks passed.

Create PR? (yes/no)
```

Wait for confirmation before proceeding.

### If Feature, User Story, Bug, or other:
Generate a UAT checklist from the acceptance criteria and present:

```
Automated checks passed and the UAT checklist is ready.

## UAT Checklist
[generated checklist here]

Please manually test the feature using the checklist above.

Did manual testing pass?
- If YES → reply "testing passed" and I will create the PR
- If NO  → describe what failed or what behaved unexpectedly
           and I will investigate and fix before asking you again
```

Wait for the user's response before proceeding. Do NOT create a PR until confirmed.

## Step 10: Push, Create PR, and Update Work Item

1. Push the branch: `git push -u origin HEAD`
2. Create a PR via Azure DevOps MCP:
   - **sourceRefName**: `refs/heads/{branch-name}`
   - **targetRefName**: `refs/heads/{BASE_BRANCH}` (the branch captured in Step 4)
   - **title**: `AB#{id}: {work item title}`
   - **labels**: `["hotfix"]` if the work item type is Hot Fix
3. Link the PR to the work item via `wit_link_work_item_to_pull_request`
4. **Close related Tasks and log hours** — see "Closing Related Tasks" below.
5. **Move the work item to `Code Review`** via `wit_update_work_item`:
   - **path**: `/fields/System.State`
   - **value**: `Code Review`

   If the project's process template does not have a `Code Review` state (the update call returns an invalid-state error), fall back in this order: `Resolved` → `In Review` → leave the current state and warn the user that the state could not be advanced automatically. Do not silently swallow the error.

### Closing Related Tasks

After the PR is created, find every child Task of this work item (relations of type `System.LinkTypes.Hierarchy-Forward` where the target's `System.WorkItemType` is `Task`). Skip this step if there are no child Tasks.

For each child Task, capture:
- ID, title, state
- `Microsoft.VSTS.Scheduling.OriginalEstimate`
- `Microsoft.VSTS.Scheduling.CompletedWork`
- `Microsoft.VSTS.Scheduling.RemainingWork`

Present:

```
## Close Related Tasks

| Task ID | Title | State | Original | Completed | Remaining |
|---------|-------|-------|----------|-----------|-----------|
| AB#xxxx | ...   | Active | 4 | 0 | 4 |
| AB#yyyy | ...   | Active | 2 | 1 | 1 |

Close all related tasks and log completed hours? (yes / no / select)
```

- `yes` → walk through every child Task in sequence
- `no`  → skip closing tasks entirely
- `select` → ask which task IDs to process; only those get prompted

For each task being processed, prompt for completed hours:

- **If `CompletedWork` is empty or `0`:**

  ```
  AB#xxxx ({title})
    Original estimate: {n}h
    Completed:         0h
    Remaining:         {n}h

  Enter completed hours (suggested: {OriginalEstimate}h, press enter to accept):
  ```

- **If `CompletedWork` is already set (non-zero):**

  ```
  AB#xxxx ({title})
    Original estimate: {n}h
    Completed:         {current}h   ← already logged
    Remaining:         {m}h

  Update completed hours to (press enter to keep {current}, or enter new value):
  ```

**Wait for the user's response on every task.** Accept the suggested/current value (enter), a new numeric value, or `skip` to leave that one untouched.

Once the user has answered, update each task via `wit_update_work_item`:
- `Microsoft.VSTS.Scheduling.CompletedWork` → the agreed value
- `Microsoft.VSTS.Scheduling.RemainingWork` → `0`
- `System.State` → `Closed` (fall back to `Done` if the project's task template uses Agile; warn if neither is valid)

Confirm with a summary line per task: `Closed AB#xxxx — {hours}h logged`.
