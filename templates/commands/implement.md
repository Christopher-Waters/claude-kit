Implement work item AB#$ARGUMENTS. Follow this workflow:

## Ultracode (opt-in — ask the user)

This command **can** orchestrate its analysis phases with the `Workflow` tool, but only if the user opts in. The user is asked once, as part of the Step 2 confirmation, whether to use Ultracode effort for this run. Do not fan out before that answer, and do not silently decide for the user.

- **If the user says yes:** apply the fan-out rules below — review (Step 8) runs as the find → adversarially-verify pipeline, and exploration / per-AC coverage (Steps 3, 7) fan out when the change is non-trivial (a full-stack story, multiple subsystems, or several acceptance criteria; skip the fan-out for a trivial single-file or config change).
- **If the user says no:** run every phase sequentially in the main loop — same steps, same gates, no `Workflow` calls.

When recommending a default in the Step 2 prompt, suggest **yes** for multi-subsystem / multi-AC work and **no** for trivial changes.

The remaining rules apply whenever Ultracode is in use:
- **Never fan out an interactive gate or a write.** Every user prompt (Steps 2, 3-approval, 8-decisions, 9) and every git / work-item mutation (Steps 4, 5, 10) stays in the **main loop**. Workflow agents here are **read-only analysts** — they use MCP read tools, `Read`, and `Grep`, and return structured findings. They do not write code, create/close work items, switch branches, or ask the user anything.
- **Stay in the loop between phases** — one short workflow per phase, read its results, present/await the user, then continue.

If the `Workflow` tool is unavailable, run each phase sequentially in the main loop — the output is identical, just slower.

## Step 1: Read the Work Item

Read the work item from Azure DevOps via MCP. Extract:
- **System.WorkItemType** — determines branch prefix
- **System.Title** — determines branch suffix
- **Acceptance criteria / description** — needed for implementation

Handle `$ARGUMENTS` as either `1234` or `AB#1234` — strip the `AB#` prefix when calling the MCP API.

**If `System.WorkItemType` is `Feature`, switch to the [Feature Workflow](#feature-workflow-ordered-story-waves) at the bottom of this document.** Steps 2–10 below describe the single-work-item flow; the Feature Workflow reuses them per child User Story.

### Embedded Images

The description and acceptance criteria fields may contain embedded images (screenshots, mockups, diagrams). These are typically `<img>` tags with `src` URLs pointing to Azure DevOps attachments. **Download and view every embedded image** using WebFetch — they often contain critical visual requirements (UI layouts, expected behavior, error states) that are not described in the text.

### Comments

Read the work item comments via `wit_list_work_item_comments`. Comments often contain clarifications, scope changes, or additional requirements added after the work item was created. Incorporate any relevant information from comments into your understanding of the work item.

## Step 2: Summarize and Confirm

### Assess reasoning effort

Reasoning effort is a **harness setting the user controls** — this command cannot change it, and no prompt or hook can. Your job is to *recommend* a level; the user applies it (via `/effort`) before the heavy work in Steps 3–8 runs. Base the recommendation on the work item's scope using this rubric (the session default is usually `high`):

| Effort | When |
|--------|------|
| `medium` | Trivial / mechanical: single-file or config change, copy tweak, one obvious fix. |
| `high` | Standard work: cross-layer change, a handful of files, normal test + review load. Recommend this unless the work is clearly lighter or heavier. |
| `xhigh` | Heavy: multi-subsystem or full-stack change, many acceptance criteria, subtle logic, tricky regressions, or ambiguous requirements. |
| `max` | Exceptional: genuinely novel design, security-critical, or high-uncertainty work. Session-only. |

Concrete signals for this command: number of subsystems/layers touched, acceptance-criteria count, and how much is net-new logic vs. following an existing pattern.

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

**Suggested reasoning effort: {level}** — {one-line justification citing the signals above}.
Effort is set by you, not me. If your current level differs, run `/effort` to adjust before replying.

Use **Ultracode effort** for this run? Ultracode fans out exploration, AC-coverage checks, and code review across parallel agents — more thorough, but slower and more token-hungry. (yes / no — suggested: {yes for multi-subsystem / multi-AC work, no for trivial changes})

Reply with your Ultracode choice (and any added context). Say **ready** once your effort level is set, or **go** to proceed at your current level.
```

**Wait for the user to respond.** Do NOT proceed until the user confirms or replies `ready`/`go`. If they add context, incorporate it into the plan. Record the Ultracode answer — it governs whether the `Workflow` fan-outs in Steps 3, 7, and 8 run at all. Never try to set the effort level yourself; only recommend it.

## Step 3: Explore & Plan

> **Ultracode (if opted in, non-trivial only):** If the work is full-stack, spans multiple subsystems, or has several acceptance criteria, fan out the exploration with `Workflow` — one read-only agent per subsystem/area, each returning the relevant files and how they relate to the requirements, plus one agent per acceptance criterion reporting what already exists and what's missing. Synthesize into a single plan in the main loop. For a trivial single-file or config change, skip the fan-out and explore directly. Either way, the plan synthesis and the approval gate stay in the main loop.

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
3. **Environment configuration parity** — if the implementation added or changed any key in `appsettings.*.json` or `.env*`, verify every parallel environment file has a corresponding entry:

   | File family | Parallel files to check |
   |-------------|------------------------|
   | `appsettings.json` | `appsettings.Development.json`, `appsettings.Staging.json`, `appsettings.QA.json`, `appsettings.Production.json` |
   | `.env` | `.env.development`, `.env.staging`, `.env.qa`, `.env.production`, `.env.local`, `.env.example` |

   Present a (key × environment) table. For every missing cell, prompt the user for a value (real, placeholder, or empty) **before creating the PR**. The PR should not be opened until every environment file is accounted for, or the user explicitly confirms the omission is intentional (e.g., the key is supplied via a pipeline variable group, Key Vault, or App Configuration for that environment).

4. **Acceptance Criteria check** — re-read the work item's full Acceptance Criteria. For each AC, identify the test or piece of code that proves it's met. If any AC has no covering test or visible code path, flag it before moving on:

   ```
   ⚠ AC #{n} ({short form}) has no covering test or clear code path.
     Add coverage now, or call this out to the user before UAT.
   ```

   Do not advance to Step 8 with any AC unverified.

   > **Ultracode (if opted in, non-trivial only):** When the story has several acceptance criteria, fan out this check with `Workflow` — one read-only agent per AC, each returning `{ac, covered: bool, evidence, gap?}`. Collect the results in the main loop and act on any `covered: false`. For a story with one or two ACs, just check them directly.

## Step 8: Code Review

> **Ultracode (if opted in):** Run the review as a `Workflow` find → verify pipeline. **Find:** fan out one agent per dimension — correctness/quality, security, Clean Architecture compliance, and CLAUDE.md adherence — each scoped to the diff and returning structured findings. **Verify:** for each finding, spawn independent skeptic agents prompted to *refute* it, and drop any finding the majority refute. Only confirmed findings reach the user. Use the `reviewer` agent type for the dimension agents (`agentType: 'reviewer'`) so they inherit its review rules. The fix/decision loop below stays in the main loop — workflow agents never edit code.

Review the diff for quality, security, Clean Architecture compliance, and CLAUDE.md adherence. Review is read-only — it reports findings, you act on them.

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

- `yes` → fix every must-fix item, then re-run the review (the Step 8 find → verify workflow) on the updated diff
- `select` → ask which items to address; fix only those, then re-run the review workflow
- `skip` → proceed without fixes (only allowed if there are no must-fix items, or the user explicitly overrides)

Loop until the review reports no must-fix items, or the user explicitly accepts remaining findings. Do not proceed to UAT with unresolved must-fix items unless the user overrides.

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

> **PR completion closes the Task only.** When this PR is later completed/merged, only the child **Task** may be closed — never the parent User Story or Bug. Azure DevOps's "Complete associated work items" option transitions *every* linked work item (including the parent this PR is linked to), so do **not** enable it when completing the PR. Close the child Task explicitly instead; the parent stays in `Code Review` until QA/UAT and any sibling Tasks are done.

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

## Feature Workflow (ordered story waves)

Used when the work item passed to `/implement` is a **Feature**. The Feature's child User Stories are implemented in **waves** driven by the custom order field (`Custom.Order`): all stories sharing the same order value run **in parallel** (one implementation agent each), and waves run sequentially in ascending order — wave 2 starts only after wave 1 is merged, built, and green, so later stories can build on earlier ones.

The single-work-item gates still exist, but they are **batched per wave** so parallel agents never have to prompt the user: one confirmation for the whole feature, one plan approval per wave, one review/UAT/PR cycle for the feature.

### F1: Load Child Stories and Build Waves

1. Fetch the Feature with `expand: Relations` (Step 1 rules apply — description, embedded images, comments).
2. Collect children (`System.LinkTypes.Hierarchy-Forward`) and fetch them via `wit_work_item` `get_batch` with fields: `System.Id`, `System.Title`, `System.State`, `System.WorkItemType`, `System.AssignedTo`, `Custom.Order`, `Microsoft.VSTS.Scheduling.StoryPoints`.
3. Keep children of type **User Story** or **Bug** that are not already `Closed`, `Resolved`, or `Removed`. List anything skipped (and why) in the F2 summary.
4. Group the remaining stories by `Custom.Order` ascending — each distinct value is one **wave**. Stories with equal order values share a wave and run in parallel.
5. Stories with **no** `Custom.Order` value form a final catch-all wave — flag them in F2 so the user can either accept that placement or set order values in Azure DevOps and re-run.
6. Read each story fully per Step 1 (description, acceptance criteria, embedded images, comments).

If the Feature has **no** implementable child stories, stop and tell the user; offer to implement the Feature itself via the standard single-work-item flow (Steps 2–10) if its own description/AC support that.

### F2: Summarize and Confirm (one gate for the whole Feature)

Present the Feature summary plus the wave plan:

```
## AB#{feature-id}: {feature title} (Feature)

**State:** {state}    **Child stories:** {n} implementable ({m} skipped: {ids + reason})

### Description
{feature description summary}

### Execution Waves (Custom.Order)

| Wave | Order | Story | Title | Points | State |
|------|-------|-------|-------|--------|-------|
| 1 | 1 | AB#6242 | ... | 3 | Dev Ready |
| 1 | 1 | AB#6243 | ... | 2 | Dev Ready |
| 2 | 2 | AB#6244 | ... | 5 | Dev Ready |
| 3 | — | AB#6245 | ... | 3 | Dev Ready |  ← no Custom.Order set; runs last

Stories in the same wave are implemented in parallel; waves run in order.

Does this look correct? Any stories to skip, reorder, or context to add?
```

Include the Step 2 reasoning-effort recommendation (a multi-story Feature is almost always `xhigh`) and the **single** Ultracode question — the answer applies to every story in the run. **Wait for the user** exactly as in Step 2.

### F3: Create the Feature Branch

Capture `BASE_BRANCH` and create `feature/AB#{feature-id}-{sanitized-title}` per Step 4 rules. All story work merges into this branch; the single PR in F7 targets `BASE_BRANCH`.

### F4: Execute Waves

For each wave in ascending order:

1. **Explore & plan** each story in the wave (Step 3 rules; Ultracode fan-outs apply per story if opted in). Present **one combined plan** with a section per story — each section covering approach, files, unit tests, and agents — plus a note on any files touched by more than one story in the wave (a conflict warning). **One approval gate per wave**; wait for the user.
2. **Implement:**
   - **Single-story wave** → implement directly on the feature branch in the main loop (Step 5).
   - **Multi-story wave** → isolate each story in its own worktree so parallel agents never clobber each other:

     ```bash
     git worktree add "{scratchpad}/wt-{story-id}" -b "story/AB#{story-id}-{sanitized-title}" "{feature-branch}"
     ```

     Launch **one implementation agent per story, all in a single message** so they run concurrently (`backend`/`frontend`/`general-purpose` per the approved plan; if a story needs both backend and frontend work, give one agent the whole story rather than splitting it). Each agent's prompt must include: the approved plan for its story, the story's full AC, its worktree path, and these rules — work **only** inside your worktree, implement the plan plus its unit tests, run the tests you added, commit to the story branch, and report what you changed. Agents never push, never create PRs, never touch work items, and never ask the user anything.
   - **Merge back (main loop):** merge each story branch into the feature branch (`git merge --no-ff`), resolving conflicts yourself using both stories' plans as the guide. Then `git worktree remove` and delete the story branch. Merge in `Custom.Order`-then-ID order so conflict resolution is deterministic.
3. **Wave gate:** run Step 6 (build validation) and Step 7.1–7.2 (full test suite + lint) on the merged feature branch. Fix failures before starting the next wave — the next wave branches from this merged, green state.

### F5: Feature-Level Quality and Review

After the last wave:

1. **Environment config parity** (Step 7.3) across the whole feature diff vs `BASE_BRANCH`.
2. **Acceptance Criteria check** (Step 7.4) for **every AC of every implemented story** — do not proceed with any AC unverified.
3. **Code review** (Step 8, including the Ultracode find → verify pipeline if opted in) over the entire feature diff, with the same must-fix loop.

### F6: UAT Gate

Present **one combined UAT checklist grouped by story** (Step 9 rules). Wait for `testing passed` before creating the PR.

### F7: PR and Work Item Updates

1. Push the feature branch and create **one PR**: title `AB#{feature-id}: {feature title}`, source `feature/...`, target `BASE_BRANCH`.
2. Link the **Feature and every implemented story** to the PR.
3. Run **Closing Related Tasks** (Step 10) once, covering the child Tasks of every implemented story — one combined table, then the usual per-task hour prompts.
4. Move each implemented story to `Code Review` (same fallback rules as Step 10). **Do not change the Feature's state** — the Feature is a parent container; it advances only when its child stories are verified/closed, not when the PR goes up for review.
5. The Step 10 PR-completion rule applies unchanged: when the PR merges, only child **Tasks** may be closed — never the stories or the Feature.
