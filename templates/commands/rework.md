Rework work item AB#$ARGUMENTS based on feedback received after the last pull request. Follow this workflow:

## Ultracode (opt-in — ask the user)

This command **can** orchestrate its analysis-heavy phases with the `Workflow` tool, but only if the user opts in. The user is asked once, as part of the Step 3 confirmation, whether to use Ultracode effort for this run. Do not fan out before that answer, and do not silently decide for the user.

- **If the user says yes:** apply the fan-out rules below and the per-step **Ultracode** callouts throughout this document.
- **If the user says no:** run every phase sequentially in the main loop — same steps, same gates, no `Workflow` calls. Skip the per-step **Ultracode** callouts.

The one exception is Step 2 (gathering feedback), which runs **before** the Step 3 prompt — run it in the main loop regardless; only fan it out if the user already opted in via the `ultracode` keyword in their invocation.

When Ultracode is in use, these rules apply:

- **Fan out the read / analyze / verify work** — gathering feedback (Step 2), exploring the codebase (Step 4), and reviewing + verifying the diff and AC coverage (Steps 9–10) are run as `Workflow` scripts with one agent per independent unit (per comment, per subsystem, per review dimension, per acceptance criterion). Each agent returns **structured findings** via a `schema`; you synthesize the results in the main loop.
- **Never fan out an interactive gate or a write.** Every user prompt (Steps 3, 4-approval, 5, 10-decisions, 11) and every work-item or git mutation (Step 5 create, Step 6 branch, Step 7 implement, Step 12 push/close) stays in the **main loop**. Workflow agents here are **read-only analysts** — they use MCP read tools, `Read`, and `Grep`, and they return data. They do not create or close work items, switch branches, write code, or ask the user anything.
- **Stay in the loop between phases.** Run one `Workflow` per phase, read its results, present/await the user as the steps require, then launch the next phase's workflow. This is several short workflows in sequence — not one monolithic run that tries to swallow the approval gates.
- **Review uses the canonical find → adversarially-verify pipeline** (Step 10): fan out per dimension, then spawn skeptic verifiers per finding and drop findings the majority refute, so only confirmed issues reach the user.

If the `Workflow` tool is somehow unavailable, fall back to running each phase sequentially in the main loop — the output is identical, just slower.

## Step 1: Find the Latest Pull Request

Handle `$ARGUMENTS` as either `1234` or `AB#1234` — strip the `AB#` prefix when calling the MCP API.

Find the most recent PR linked to this work item:

1. Read the work item via MCP and note its **relations** — look for pull request artifact links
2. For each linked PR, fetch its details via `repo_get_pull_request_by_id` and record the **creationDate**
3. Identify the **most recent PR** by creation date — this is the baseline for detecting new feedback

Save the PR's `creationDate` as `LAST_PR_DATE` — everything after this timestamp is new feedback.

## Step 2: Gather Rework Feedback

> **Ultracode (if opted in):** Fan out the gathering with `Workflow` — one agent per new comment (parse its text and **download + view every embedded image** via `WebFetch`), plus one agent analyzing the description / acceptance-criteria revisions since `LAST_PR_DATE`. Each agent returns a structured feedback item (`{source, summary, imageObservations, referencedAC?}`). Synthesize them into the Step 3 list in the main loop. Reading and image analysis are independent per comment — this is the fan-out unit.

### New Comments

Read the work item comments via `wit_list_work_item_comments`. Filter to only comments created **after** `LAST_PR_DATE`. These contain the rework feedback.

For each new comment, check for embedded images (`<img>` tags with `src` URLs pointing to Azure DevOps attachments). **Download and view every embedded image** using WebFetch — they often contain screenshots of bugs, visual issues, or annotated UI showing what needs to change.

### Description & Acceptance Criteria Changes

Read the work item revisions via `wit_list_work_item_revisions`. Check if the **description** or **acceptance criteria** fields were modified **after** `LAST_PR_DATE`.

- If changed: extract the **current** description and acceptance criteria, and note what was added or modified
- If unchanged: still read the current description and acceptance criteria — a comment may reference something that was in the original requirements but missing from the implementation

### Always Re-read Requirements

Regardless of whether description/acceptance criteria changed, **always read the full current description and acceptance criteria**. Rework comments often say things like "the original requirement for X is missing" without the description itself changing. You need the full context to understand what the feedback is referring to.

## Step 3: Summarize Rework and Confirm

Present a summary of the rework feedback to the user. **Every feedback item must be mapped to an Acceptance Criterion** — if a feedback item doesn't map to any AC, flag it explicitly as either (a) implied by an AC that's worded too loosely or (b) scope-creep that should be a separate work item.

```
## Rework for AB#{id}: {title}

**Last PR:** #{pr_id} (created {date})
**New comments:** {count}

### Current Acceptance Criteria
1. {AC #1 — verbatim}
2. {AC #2 — verbatim}
3. ...

### Rework Feedback → AC mapping
| # | Feedback (summarized) | Maps to AC | Status |
|---|----------------------|-----------|--------|
| 1 | {feedback item 1}    | AC #2     | not met in last PR |
| 2 | {feedback item 2}    | AC #4     | partially met — edge case missed |
| 3 | {feedback item 3}    | (none)    | ⚠ scope-creep — flag for separate item? |

### Requirement Changes (if any)
{description/acceptance criteria changes since last PR, or "No changes to description or acceptance criteria since last PR"}

Does this capture the rework correctly? Any feedback items that should be flagged as scope-creep (separate work item) instead of being addressed here?

Use **Ultracode effort** for this rework? Ultracode fans out exploration, AC-coverage checks, and code review across parallel agents — more thorough, but slower and more token-hungry. (yes / no — suggested: {yes for multi-file / multi-AC rework, no for a small targeted fix})
```

**Wait for the user to respond.** Do NOT proceed until the user confirms the AC mapping. Record the Ultracode answer — it governs whether the `Workflow` fan-outs in Steps 4, 9, and 10 run at all. If they reclassify any item as scope-creep, drop it from the plan and note it in the final summary. If they add context, incorporate it.

## Step 4: Explore & Plan

> **Ultracode (if opted in):** Fan out the exploration with `Workflow` — one read-only agent per subsystem touched by the last PR (and per new area the feedback implies), each returning the relevant files and how they relate to the feedback. In the same pass, fan out **one agent per acceptance criterion** to report whether the current code covers it and what's missing. Synthesize all findings into a single plan in the main loop, then present it. Exploration and per-AC coverage analysis are independent — fan them out; the plan synthesis and the approval gate stay in the main loop.

1. **Explore** the codebase to map relevant files — focus on files changed in the last PR and any new areas needed
2. **Plan** the rework approach

Present the plan to the user:

```
## Rework Plan for AB#{id}

### Approach
{brief description of what needs to change to address the feedback}

### Files to Create
- `path/to/new/file.cs` — {purpose}
- `path/to/new/file.tsx` — {purpose}

### Files to Modify
- `path/to/existing/file.cs` — {what changes and why}
- `path/to/existing/file.tsx` — {what changes and why}

### Files to Delete (if any)
- `path/to/old/file.cs` — {why it's being removed}

### Unit Tests
- `path/to/new.tests.cs` — covers {scenario the rework adds or fixes}
- `path/to/existing.tests.cs` — updates assertions for {changed behavior}

List every test file you will add or modify and the scenarios each covers. Rework feedback often reveals missing test coverage on the original implementation — add regression tests that would have caught the original issue. If a rework change in this plan has no test coverage, justify why here.

### Acceptance Criteria Coverage
For every AC on the work item, state how this plan ensures it is met after rework. The rework is not complete until every row is "covered." Use this table — do not skip any AC, even ones the feedback didn't mention.

| AC # | Acceptance Criterion (short) | How this plan covers it |
|------|------------------------------|--------------------------|
| 1    | {AC #1 short form}           | Already met by prior PR — verify via {test or manual check} |
| 2    | {AC #2 short form}           | Addressed by {file/change} + {test} |
| 3    | {AC #3 short form}           | ⚠ Not yet covered — {what needs to be added to this plan before approving} |

If any row reads "⚠ Not yet covered," fix the plan before presenting it — do not ask the user to approve an incomplete plan.

### Agents
- **backend**: {what it will do}
- **frontend**: {what it will do}

### Risks / Considerations
- {any potential issues or trade-offs}

Approve this plan? (yes / no / suggest changes)
```

**Wait for the user to approve the plan.** Do NOT start implementation until the user approves. If they suggest changes, revise the plan and present it again.

## Step 5: Create Rework Task as a Child

Every rework round gets its own Task work item, parented under the original User Story / Bug. This keeps the rework effort visible on the board and gives the team a clean record of how many rounds an item went through.

### Suggest hours

Estimate the rework effort from the approved plan. Use this rubric — calibrate against scope, not abstract complexity:

| Hours | Looks like |
|-------|-----------|
| **0.5** | Trivial — copy tweak, single config value, one-line fix. No new tests. |
| **1**   | One file, well-understood change. Maybe one new/updated test. |
| **2**   | 2–3 files, one layer, follows existing patterns. Some new tests. |
| **4**   | Multiple files across layers, or new logic in one area. Real test coverage. |
| **8**   | Most of a day — meaningful new logic, several files, edge cases. |
| **16**  | Two days — significant rework, multiple unknowns to resolve. |
| **24+** | Three days or more — flag that this rework probably should have been a fresh story. |

Adjust upward for: ambiguous feedback, missing UX, data migrations, regression risk in unrelated areas. Adjust downward for: pure config changes or mechanical fixes.

### Prompt the user

```
## Rework Task

**Title:**       Rework AB#{id} — round {N}
**Parent:**      AB#{id} ({title})
**Description:** {1–2 sentence summary of the rework feedback addressed}

**Suggested hours:** {n}
  Based on: {one line — files touched / scope / unknowns}

Enter the estimated hours for this task (press enter to accept {n}):
```

`{N}` is the rework round — count how many existing child Tasks already exist on the parent with a title matching `Rework AB#{id}` and add 1.

**Wait for the user's response.** Accept the suggestion (enter), accept a different number, or `cancel` to skip task creation. Do not proceed to branch switch until this is resolved.

### Create the task

If the user provided hours (suggested or overridden):

1. Call `mcp__azure-devops__wit_create_work_item`:
   - **workItemType**: `Task`
   - **title**: `Rework AB#{id} — round {N}`
   - **fields**: JSON Patch document setting:
     - `System.Description` — structured **HTML** (Azure DevOps does not render Markdown in this field). Use exactly these three sections, in this order, omitting any that have no content:

       ```html
       <h3>Summary</h3>
       <p>{1–2 sentences describing the problem the rework addresses. Bold key terms, values, and outcomes with <strong>...</strong>.}</p>
       <h3>Fix</h3>
       <ul>
         <li>{What changes. Wrap code identifiers, method names, fields, file paths, and literal values in <code>...</code>.}</li>
       </ul>
       <h3>Reference</h3>
       <ul>
         <li>Rework round {N} of AB#{id} ({date or tester} feedback).</li>
         <li><a href="{PR url}">PR #{n}</a> — {one-line context, e.g. test-plan scenario, submission id in <code>...</code>}</li>
       </ul>
       ```

       Render any code identifiers (method names, fields, file paths, hashes, literal values) inside `<code>` spans, and emphasize the key claim/value in each sentence with `<strong>`. Do not submit a wall of plain prose — every rework task must have at least the `Summary` and `Fix` sections in this shape.
     - `Microsoft.VSTS.Scheduling.OriginalEstimate` — the agreed hours
     - `Microsoft.VSTS.Scheduling.RemainingWork` — the agreed hours
     - `System.AreaPath` — same as the parent
     - `System.IterationPath` — same as the parent
     - `System.AssignedTo` — same as the parent (copy the parent's `System.AssignedTo` value; pass the `uniqueName` / email if the parent's value is an identity object). If the parent is unassigned, leave this field unset rather than failing.

2. Link the new Task as a child of the parent work item via `wit_work_items_link`:
   - **type**: `Child` (the parent → child link from the parent's perspective; equivalent to `Parent` from the task's perspective)
   - **source**: parent work item ID
   - **target**: new task ID

3. Confirm to the user: `Created task AB#{taskId} (parent: AB#{id}, est: {hours}h)`.

If the user cancels, skip task creation and proceed — note "No rework task created" in the final summary.

## Step 6: Switch to Existing Branch

The work item already has a branch from the previous PR. Switch to it:

1. Get the source branch name from the most recent PR
2. Switch to that branch: `git checkout <branch-name>`
3. Pull the latest: `git pull`

If the PR was completed/merged and the branch was deleted, create a new branch from the PR's target branch following the same naming convention as `/implement` Step 4.

## Step 7: Implement

1. **Implement** the rework using backend and/or frontend agents according to the approved plan
2. **Write the unit tests** listed in the plan's "Unit Tests" section alongside the implementation — not after. Include any regression test that would have caught the original issue
3. **Generate mockup** if there are UI changes

## Step 8: Build Validation

Run a build check **before** any other quality checks. Use the `build-validator` agent to verify that all projects compile successfully.

- If the build fails, **fix the errors immediately** and re-run until the build passes
- Do NOT proceed to review, tests, or lint until the build is clean

## Step 9: Quality Checks

1. **Run the full test suite** — every unit test in the repo, plus integration tests. Not just the tests added in this rework. A failure in an unrelated test means this rework broke something else; treat it as a regression, fix it, and re-run until the entire suite is green
2. **Run lint** — ESLint and dotnet format
3. **Environment configuration parity** — if the rework added or changed any key in `appsettings.*.json` or `.env*`, verify every parallel environment file (Development/Staging/QA/Production for backend; `.env.development`/`.env.staging`/`.env.production`/`.env.example` for React — whichever exist in the repo) has a corresponding entry. Present a (key × environment) table. Prompt the user to fill in any missing values (real, placeholder, or empty) **before pushing**, or to explicitly confirm the omission is intentional (e.g., supplied via a pipeline variable group, Key Vault, or App Configuration).
4. **Acceptance Criteria check** — re-read the work item's full Acceptance Criteria (the same list captured in Step 3). For each AC, identify the test or piece of code that proves it's met. If any AC has no covering test or visible code path, flag it before moving on.

   > **Ultracode (if opted in):** Fan out this check with `Workflow` — one read-only agent per acceptance criterion, each returning `{ac, covered: bool, evidence, gap?}`. Collect the results in the main loop and act on any `covered: false`.

   ```
   ⚠ AC #{n} ({short form}) has no covering test or clear code path.
     Add coverage now, or call this out to the user before UAT.
   ```

   Do not advance to Step 10 with any AC unverified.

## Step 10: Code Review

> **Ultracode (if opted in):** Run the review as a `Workflow` find → verify pipeline. **Find:** fan out one agent per dimension — correctness/quality, security, Clean Architecture compliance, CLAUDE.md adherence, and regression risk from the rework — each scoped to the files changed since the last PR and returning structured findings. **Verify:** for each finding, spawn independent skeptic agents prompted to *refute* it, and drop any finding the majority refute. Only confirmed findings reach the user. Use the `reviewer` agent type for the dimension agents (`agentType: 'reviewer'`) so they inherit its review rules. The fix/decision loop below stays in the main loop — workflow agents never edit code.

Review the rework diff for quality, security, Clean Architecture compliance, and CLAUDE.md adherence. Focus the review on the files changed since the last PR — call out any regression risk introduced by the rework. Review is read-only — it reports findings, you act on them.

Present the confirmed findings to the user grouped by severity:

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

- `yes` → fix every must-fix item, then re-run the review (the Step 10 find → verify workflow) on the updated diff
- `select` → ask which items to address; fix only those, then re-run the review workflow
- `skip` → proceed without fixes (only allowed if there are no must-fix items, or the user explicitly overrides)

Loop until the review reports no must-fix items, or the user explicitly accepts remaining findings. Do not proceed to UAT with unresolved must-fix items unless the user overrides.

## Step 11: UAT Gate

### If Hot Fix:
Skip manual UAT. Present an abbreviated confirmation:

```
Rework complete. All automated checks passed.

Push changes? (yes/no)
```

Wait for confirmation before proceeding.

### If Feature, User Story, Bug, or other:
Generate a UAT checklist from the acceptance criteria and present:

```
Automated checks passed and the UAT checklist is ready.

## UAT Checklist
[generated checklist here — highlight items specific to the rework feedback]

Please manually test the rework using the checklist above.

Did manual testing pass?
- If YES → reply "testing passed" and I will push the changes
- If NO  → describe what failed or what behaved unexpectedly
           and I will investigate and fix before asking you again
```

Wait for the user's response before proceeding. Do NOT push until confirmed.

## Step 12: Push and Update

1. Push the changes: `git push`
2. Add a comment on the existing PR summarizing what was changed in the rework
3. **Close related Tasks and log hours** — see "Closing Related Tasks" below. This includes the rework Task created in Step 5 as well as any other child Tasks that became `Completed` as a result of this rework round.
4. **Move the work item back to `Code Review`** via `wit_update_work_item`:
   - **path**: `/fields/System.State`
   - **value**: `Code Review`

   Rework is triggered by reviewer feedback, so the item was likely in `Active` / `In Progress` / `Rework` while the fixes were being made. Pushing the rework hands it back to the reviewer, so it belongs in `Code Review` again.

   If the project's process template does not have a `Code Review` state (the update call returns an invalid-state error), fall back in this order: `Resolved` → `In Review` → leave the current state and warn the user. Do not silently swallow the error.

> **PR completion closes the Task only.** When the PR is later completed/merged, only the child **Task** may be closed — never the parent User Story or Bug. Azure DevOps's "Complete associated work items" option transitions *every* linked work item (including the parent the PR is linked to), so do **not** enable it when completing the PR. Close the child Task explicitly instead; the parent stays in `Code Review` until QA/UAT and any sibling Tasks are done.

### Closing Related Tasks

After pushing, find every child Task of this work item (relations of type `System.LinkTypes.Hierarchy-Forward` where the target's `System.WorkItemType` is `Task`). Skip this step if there are no child Tasks.

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
| AB#xxxx | Rework AB#{id} — round 2 | Active | 4 | 0 | 4 |
| AB#yyyy | ...                      | Active | 2 | 1 | 1 |

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
