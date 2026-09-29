Rework work item AB#$ARGUMENTS based on feedback received after the last pull request. Follow this workflow:

## Ultracode (opt-in — ask the user)

This command **can** orchestrate its analysis-heavy phases with the `Workflow` tool, but only if the user opts in. The user is asked once, as part of the Step 3 confirmation, whether to use Ultracode effort for this run. Do not fan out before that answer, and do not silently decide for the user.

- **If the user says yes:** apply the fan-out rules below and the per-step **Ultracode** callouts throughout this document.
- **If the user says no:** run every phase sequentially in the main loop — same steps, same gates, no `Workflow` calls. Skip the per-step **Ultracode** callouts.

The one exception is Step 2 (gathering feedback), which runs **before** the Step 3 prompt — run it in the main loop regardless; only fan it out if the user already opted in via the `ultracode` keyword in their invocation.

When Ultracode is in use, these rules apply:

- **Fan out the read / analyze / verify work** — gathering feedback (Step 2), exploring the codebase (Step 4), and reviewing + verifying the diff and AC coverage (Steps 9–10) are run as `Workflow` scripts with one agent per independent unit (per comment, per subsystem, per review dimension, per acceptance criterion). Each agent returns **structured findings** via a `schema`; you synthesize the results in the main loop.
- **Never fan out an interactive gate or a write.** Every user prompt (Steps 3, 4-approval, 5, 10-decisions, 11) and every work-item or git mutation (Step 0 worktree, Step 5 create, Step 6 branch, Step 7 implement, Step 12 push/close, Step 13 cleanup) stays in the **main loop**. Workflow agents here are **read-only analysts** — they use MCP read tools, `Read`, and `Grep`, and they return data. They do not create or close work items, switch branches, write code, or ask the user anything.
- **Give every Workflow agent the ticket's worktree path** (Step 0) — that is where the code under analysis lives, not the folder the session started in.
- **Stay in the loop between phases.** Run one `Workflow` per phase, read its results, present/await the user as the steps require, then launch the next phase's workflow. This is several short workflows in sequence — not one monolithic run that tries to swallow the approval gates.
- **Review uses the canonical find → adversarially-verify pipeline** (Step 10): fan out per dimension, then spawn skeptic verifiers per finding and drop findings the majority refute, so only confirmed issues reach the user.

If the `Workflow` tool is somehow unavailable, fall back to running each phase sequentially in the main loop — the output is identical, just slower.

## Step 1: Find the Latest Pull Request

Handle `$ARGUMENTS` as either `1234` or `AB#1234` — strip the `AB#` prefix when calling the MCP API. If it also says "work in place" or "no worktree", strip that and remember it for Step 0.

Find the most recent PR linked to this work item:

1. Read the work item via MCP and note its **relations** — look for pull request artifact links
2. For each linked PR, fetch its details via `repo_get_pull_request_by_id` and record the **creationDate**
3. Identify the **most recent PR** by creation date — this is the baseline for detecting new feedback

Save the PR's `creationDate` as `LAST_PR_DATE` — everything after this timestamp is new feedback. Also save its **source branch** and **target branch** (`sourceRefName` / `targetRefName`, minus `refs/heads/`) — Step 0 needs both.

## Step 0: Set Up the Ticket's Workspace

Developers run several Claude Code sessions against the same repo at once, one per ticket. If every session `git checkout`s in the folder it started in, they clobber each other's working tree. So each ticket gets its own **git worktree** in a sibling folder, `../{repo}-AB{id}` (e.g. `../CSIPay-AB5373`), and every later step runs there. The folder the session started in is never checked out, committed to, or edited.

It is Step 0 because it comes before anything touches the code. It runs **right after Step 1**, because it needs the branches of the PR Step 1 found, and Step 1 only reads Azure DevOps. It is setup, not a gate: it prompts only where a case below says so.

**Opt-out.** If the user says **"work in place"** or **"no worktree"** — in the invocation (`/rework 1234 work in place`; strip the phrase before reading the id) or at any point before Step 6 — skip this step, skip Step 13, and ignore every worktree note below: the command runs exactly as it did before worktrees, switching branches in the current folder in Step 6. If Step 0 has already run, give back the worktree it made (nothing has changed in it yet): `git worktree unlock "{WT}"`, then `git worktree remove "{WT}"`, then carry on in place.

Shell variables do not survive between Bash calls. Resolve each value once, then write the **literal absolute paths and branch names** into every later command. Below, `SOURCE` and `TARGET` are the latest PR's source and target branches from Step 1.

### 0a. Resolve the repo and fetch

```bash
git worktree list --porcelain | sed -n '1s/^worktree //p'   # MAIN — the main checkout
git fetch --prune origin
git worktree prune
```

- **`MAIN`** is the first entry of `git worktree list` — the main checkout, even when the session started in a subfolder or inside another ticket's worktree (`--show-toplevel` would return that worktree, and the new one would land at `CSIPay-AB5375-AB5380`).
- **`REPO`** is `basename` of `MAIN`; **`WT`** is `{dirname of MAIN}/{REPO}-AB{id}` — always the absolute path.
- **`--prune`** matters: without it a branch deleted on the remote after its PR merged still looks alive locally, so 0c would never take the merged-branch fallback and 0b's "deleted on the remote" check would never fire.
- **`git worktree prune`** forgets worktrees whose folders were deleted by hand, so a stale leftover can be recreated cleanly.

### 0b. Tidy other tickets' worktrees

Look at every **other** worktree in `git worktree list --porcelain` whose folder is named `{REPO}-AB*`. Never touch `MAIN`, this ticket's `WT`, a worktree on `SOURCE` or on another `*/AB#{id}-*` branch (0c reuses it), or any folder outside that naming pattern.

- **Locked → skip it.** A lock means another session is working in it right now; 0c locks every worktree it hands out.
- **Otherwise remove it only if all three hold:**
  1. **Nothing uncommitted** — `git -C "{path}" status --porcelain` prints nothing.
  2. **Nothing unpushed** — its branch has an upstream, and either `git -C "{path}" rev-list --count '@{u}..HEAD'` prints `0`, or the upstream is **gone** (`git -C "{path}" for-each-ref --format='%(upstream:track)' "refs/heads/{branch}"` prints `[gone]` — its PR merged and the remote branch was deleted). For a gone upstream, also confirm nothing was committed after the last push: find the branch's pull request (`repo_pull_request`, by source branch, any status) and check its `lastMergeSourceCommit` equals `git -C "{path}" rev-parse HEAD`. A branch that was **never pushed** (no upstream), a detached HEAD, a HEAD that differs from what the PR merged, or no PR found — all fail this check.
  3. **Merged, or deleted on the remote** — the upstream is `[gone]`, or `git -C "{MAIN}" merge-base --is-ancestor "{branch}" "origin/{TARGET}"` succeeds.

  Remove with `git -C "{MAIN}" worktree remove "{path}"`, then `git -C "{MAIN}" branch -D "{branch}"`. **Never `--force`, never `rm` the folder.** If a removal fails because another session removed it first, ignore that and move on.
- **Anything else stays.** List what was kept in one line, with the reason — `Kept: ../CSIPay-AB5301 (2 uncommitted files), ../CSIPay-AB5310 (locked — another session, or abandoned: git worktree unlock "{path}")`.

### 0c. Put the worktree on the PR's branch

Take the first case that matches:

1. **A worktree is already on `SOURCE`** — a `branch refs/heads/{SOURCE}` line in `git worktree list --porcelain` → use that worktree as `WT`, wherever it is (a hand-made folder, or even `MAIN` itself). Don't create a second one, and don't fail because the branch is checked out elsewhere. Bring it up to date with `git -C "{WT}" pull --ff-only`.
2. **`WT` is already a worktree, but on something else** (a detached HEAD, another branch) → show `git -C "{WT}" status -sb` and ask whether to switch it to `SOURCE` or stop.
3. **`WT` exists but git doesn't know it** (not in the list even after 0a's prune) → stop and ask the user to delete or rename it. Its contents aren't in git, so there is no way to tell whether anything in it is worth keeping.
4. **`SOURCE` is still on origin** (`git -C "{MAIN}" rev-parse --verify --quiet "refs/remotes/origin/{SOURCE}"` succeeds) → check it out, tracking `origin/{SOURCE}`:
   - **No local branch:**

     ```bash
     git -C "{MAIN}" worktree add --track -b "{SOURCE}" "{WT}" "origin/{SOURCE}"
     ```
   - **A local branch exists:** run `git -C "{MAIN}" worktree add "{WT}" "{SOURCE}"`, then `git -C "{WT}" branch --set-upstream-to "origin/{SOURCE}"`, then `git -C "{WT}" pull --ff-only`.

   If `pull --ff-only` fails, the local branch and origin have diverged. Stop and show both sides (`git -C "{WT}" log --oneline --left-right '@{u}...HEAD'`). Never merge, rebase, or reset without asking.
5. **`SOURCE` was deleted** (its PR merged) → create a new branch from the PR's **target**. Name it by `/implement` Step 4's convention (`{prefix}AB#{id}-{sanitized-title}`) — the rule from before worktrees, now inside the worktree:

   ```bash
   git -C "{MAIN}" worktree add --no-track -b "{new-branch}" "{WT}" "origin/{TARGET}"
   ```

   It has no upstream until Step 12 pushes it with `-u`. If `-b` fails because a leftover local branch has that name, show what it holds that the target doesn't (`git -C "{MAIN}" log --oneline "origin/{TARGET}..{new-branch}"`) and ask whether to delete it (`git -C "{MAIN}" branch -D "{new-branch}"`) and retry, or reuse it.

Then **lock it** so another session's 0b leaves it alone — a clean, fully pushed worktree would otherwise pass every tidy check the moment its PR merges:

```bash
git -C "{MAIN}" worktree lock --reason "AB#{id} — /rework in progress" "{WT}"
```

Skip the lock when `WT` is `MAIN` (the main checkout can't be locked, and 0b never touches it). If the worktree is **already locked**, another session may still be working this ticket. Say so in one line — `AB#{id}'s worktree is locked ({reason}) — if another session is still on this ticket, both will edit the same files` — and carry on in it.

### 0d. Copy the local files git doesn't carry

A new worktree has only tracked files. Copy in `.claude/settings.local.json` (the user's local permission rules) and every gitignored `.env.local` / `*.local.json`. Copy nothing that already exists in the worktree:

```bash
cd "{MAIN}" && {
  [ -f .claude/settings.local.json ] && echo .claude/settings.local.json
  git ls-files --others --ignored --exclude-standard -- ':(glob)**/.env.local' ':(glob)**/*.local.json' ':(exclude,glob)**/node_modules/**'
} | sort -u | while IFS= read -r f; do
  [ -e "{WT}/$f" ] || { mkdir -p "{WT}/$(dirname "$f")" && cp "$f" "{WT}/$f"; }
done
```

**None of these may ever be committed.** The `.env.local` / `*.local.json` files are gitignored by construction. `.claude/settings.local.json` may not be, so if `git -C "{WT}" check-ignore -q .claude/settings.local.json` fails, append `.claude/settings.local.json` to `{MAIN}/.git/info/exclude`. That file is local and shared by every worktree of the repo, so the exclude covers them all and is itself never committed.

`node_modules` is not copied. Step 7 installs it, only when the plan touches the frontend.

### 0e. Work only in the ticket's worktree

- **Every later step runs in `WT`** — exploration, implementation, build, tests, lint, commits, review. Claude Code can reset the shell to the session's folder between calls, so run git as `git -C "{WT}" …`, run everything else as `cd "{WT}" && …`, and use absolute paths for `Read`/`Edit`/`Write`.
- **Pass `WT` to every subagent and Workflow agent**, in so many words: `The code for AB#{id} is in {WT}. Read, edit, build, and test only there — never in {MAIN}.`
- **Diff against `origin/{TARGET}`**, not `{TARGET}`, wherever a later step compares with the PR's target — the local branch may be behind.
- **Quote every branch name** — the `#` in `story/AB#5373-…` starts a comment or a glob in some shells.
- `WT` is outside the folder the session started in, so Claude Code asks before the first edit there. Tell the user once, in the report below.
- Sessions sharing a repo still share **local ports and the Dev database**. If this ticket's dev server or integration tests collide with another session's, run them one at a time.

Report the workspace in one short block, then go on to Step 2:

```
Workspace for AB#{id}: {WT}
  {reused, on {SOURCE} | new, on {SOURCE} from origin | new branch {new-branch} from origin/{TARGET} — PR #{n}'s branch was deleted}
  Tidied: {removed worktrees, or "nothing to tidy"}    Kept: {kept worktrees + reason, or omit}
  Edits there need approval once — run `/add-dir {WT}` to allow them for this session.
```

## Step 2: Gather Rework Feedback

> **Ultracode (if opted in):** Fan out the gathering with `Workflow` — one agent per new comment (parse its text and **download + view every embedded image** via `WebFetch`), plus one agent analyzing the description / acceptance-criteria revisions since `LAST_PR_DATE`. Each agent returns a structured feedback item (`{source, summary, imageObservations, referencedAC?}`). Synthesize them into the Step 3 list in the main loop. Reading and image analysis are independent per comment — this is the fan-out unit.

### New Comments

Read the work item comments via `wit_work_item` (action `list_comments`). Filter to only comments created **after** `LAST_PR_DATE`. These contain the rework feedback.

For each new comment, check for embedded images (`<img>` tags with `src` URLs pointing to Azure DevOps attachments). **Download and view every embedded image** using WebFetch — they often contain screenshots of bugs, visual issues, or annotated UI showing what needs to change.

### Description & Acceptance Criteria Changes

Read the work item revisions via `wit_work_item` (action `list_revisions`). Check if the **description** or **acceptance criteria** fields were modified **after** `LAST_PR_DATE`.

- If changed: extract the **current** description and acceptance criteria, and note what was added or modified
- If unchanged: still read the current description and acceptance criteria — a comment may reference something that was in the original requirements but missing from the implementation

### Always Re-read Requirements

Regardless of whether description/acceptance criteria changed, **always read the full current description and acceptance criteria**. Rework comments often say things like "the original requirement for X is missing" without the description itself changing. You need the full context to understand what the feedback is referring to.

## Step 3: Summarize Rework and Confirm

### Assess reasoning effort

Reasoning effort is a **harness setting the user controls** — this command cannot change it, and no prompt or hook can. Recommend a level; the user applies it (via `/effort`) before the rework in Steps 4–10 runs. Base it on the rework's scope using this rubric (the session default is usually `high`):

| Effort | When |
|--------|------|
| `medium` | A small targeted fix: one or two files, a single low-risk feedback item. |
| `high` | Standard rework: a handful of files, a few feedback items across a layer or two. Recommend this unless clearly lighter or heavier. |
| `xhigh` | Heavy rework: multi-subsystem changes, many feedback items / ACs, subtle regressions, or ambiguous feedback. |
| `max` | Exceptional: the feedback exposes a design flaw needing a rethink, or security-critical work. Session-only. |

Concrete signals for this command: number of feedback items, how many ACs they map to, and how many subsystems the fixes touch.

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

**Suggested reasoning effort: {level}** — {one-line justification citing the signals above}.
Effort is set by you, not me. If your current level differs, run `/effort` to adjust before replying.

Use **Ultracode effort** for this rework? Ultracode fans out exploration, AC-coverage checks, and code review across parallel agents — more thorough, but slower and more token-hungry. (yes / no — suggested: {yes for multi-file / multi-AC rework, no for a small targeted fix})

Reply with your Ultracode choice (and any reclassifications or context). Say **ready** once your effort level is set, or **go** to proceed at your current level.
```

**Wait for the user to respond.** Do NOT proceed until the user confirms the AC mapping and replies `ready`/`go`. Record the Ultracode answer — it governs whether the `Workflow` fan-outs in Steps 4, 9, and 10 run at all. If they reclassify any item as scope-creep, drop it from the plan and note it in the final summary. If they add context, incorporate it. Never try to set the effort level yourself; only recommend it.

## Step 4: Explore & Plan

> **Ultracode (if opted in):** Fan out the exploration with `Workflow` — one read-only agent per subsystem touched by the last PR (and per new area the feedback implies), each returning the relevant files and how they relate to the feedback. In the same pass, fan out **one agent per acceptance criterion** to report whether the current code covers it and what's missing. Synthesize all findings into a single plan in the main loop, then present it. Exploration and per-AC coverage analysis are independent — fan them out; the plan synthesis and the approval gate stay in the main loop.

1. **Explore** the codebase to map relevant files — focus on files changed in the last PR and any new areas needed
2. **Plan** the rework approach
3. **Re-analyze the plan as an architect** — the pass below, before the user sees anything

### Architect Review (runs before the plan is presented)

The draft plan is a first answer, not the answer. Re-read it cold — as an experienced architect who did not write it and who cares what this codebase looks like a year from now. This happens on **every** rework plan, before the user sees anything.

> **Ultracode:** run this as a separate `Workflow` agent so the review is actually independent. Give it the work item, the acceptance criteria, the rework feedback, and the draft plan — but **not** your reasoning for the plan — and have it read the affected files itself. A reviewer who has seen the author's justification anchors to it.

Each question below is about a cost that is cheap now and expensive once the code exists:

| # | Question | What a bad answer looks like |
|---|----------|------------------------------|
| 1 | **Does this already exist?** A service, hook, component, or extension method that already does this, or is one call away. | A new `PaymentExportService` beside the `ExportService` that already handles three other exports |
| 2 | **Is each piece in the right layer?** Domain / Application / Infrastructure / API boundaries hold — no business rules in a controller, no Mongo or EF types in Domain, no HTTP concepts below API. | An `IMongoCollection<T>` parameter on a Domain method |
| 3 | **What is the simplest plan that still meets every AC?** State it, then adopt it or say in one line why the heavier one is needed. | An interface with exactly one implementation, added "for testability" |
| 4 | **What else touches the files being modified?** Name the callers. A change to a shared contract, DTO, or response shape is a breaking change until proven otherwise. | Editing a shared DTO with no note about its other consumers |
| 5 | **What happens to data that already exists?** New required fields, schema changes, and backfills each need an answer for rows written before this change — and the answer should run itself: the project's run-once migration mechanism if it has one, not a script someone has to remember in every environment (see **Deployment Scripts** in CLAUDE.md). | A non-nullable field added with no default and no backfill; a `backfill.js` to run by hand on test, staging and prod when the API already runs one-time migrations at startup |
| 6 | **How does it fail?** Partial failure, concurrent callers, a retried request. Is the operation idempotent, and does it need to be? | A multi-step write with no story for a crash between steps |
| 7 | **Does it hold at real data volume?** Queries inside loops, unbounded result sets, a missing index, a list endpoint with no paging. | A `foreach` over accounts issuing one query each |
| 8 | **Is it safe?** Authorization on every new endpoint, and **no sensitive field** (TIN, SSN, EIN, TaxId, BankAccountNumber, RoutingNumber, any `Encrypted*`) read, logged, returned, or projected — see the sensitive-data rule in CLAUDE.md. | A new endpoint returning a whole entity because it was convenient |
| 9 | **Can it be tested without heavy mocking?** A test needing five mocks is telling you the seams are in the wrong place. | A test plan that starts "mock the repository, the clock, and the HTTP client" |
| 10 | **Can it be undone?** `/rollback` reverts commits; it does not un-migrate data or un-send an email. Flag anything one-way. | A destructive migration with no reverse path |
| 11 | **Cause or symptom?** Rework feedback reports an instance. Does this plan fix why it happened, or only the case that was reported? | Special-casing the one date the tester tried |
| 12 | **What did the original PR get right that this could undo?** It passed review once. Name what this change puts back at risk, and the regression test that pins it. | A rewrite of a method whose edge cases were the point of the original review |

**Two hard limits on this pass:**

- **It may not grow the scope.** It exists to simplify, correct, and de-risk — not to add caching, abstraction layers, or features nobody asked for. Anything outside the acceptance criteria goes in *Risks / Considerations*, or becomes a separate work item you mention. It is never folded into the plan silently.
- **It may not invent findings.** If the plan survives every question, say so in one line. A manufactured concern to look thorough spends the user's attention at the one gate that is supposed to protect it.

Apply what the pass finds, then report it in the plan as the **Architect Review** section below. The pass is never skipped; only its output scales — on a one-file config change most rows answer themselves and the report is two lines.

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

### Data Changes (if any)
- {what changes in existing data} — **automated** by {the project's run-once mechanism}: `{file}`
- {what changes in existing data} — **hand-run** `{script path}`, because {which Deployment Scripts reason applies}. Attached to the work item when the PR goes up.

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

### Architect Review
{One line per change the review made: what the draft said → what it says now → why.}
{If nothing changed: "Reviewed against every question — no changes." plus the one that came closest to a finding and why it is fine.}

Approve this plan? (yes / no / suggest changes)
```

**Wait for the user to approve the plan.** Do NOT start implementation until the user approves. If they suggest changes, revise the plan and present it again.

## Step 5: Create Rework Task as a Child

Every rework round gets its own Task work item, parented under the original User Story / Bug. This keeps the rework effort visible on the board and gives the team a clean record of how many rounds an item went through.

### Suggest hours

Estimate the rework effort from the approved plan. The rows below are **scope** — how much there is to change. Where you land between two adjacent rows is **complexity** — how settled the change is:

A day is **6 productive hours**; a week is 5 days (30 hours).

| Hours | Looks like |
|-------|-----------|
| **0.5** | Trivial — copy tweak, single config value, one-line fix. No new tests. |
| **1**   | One file, well-understood change. Maybe one new/updated test. |
| **2**   | 2–3 files, one layer, follows existing patterns. Some new tests. |
| **3**   | Half a day — multiple files across layers, or new logic in one area. Real test coverage. |
| **6**   | A full day — meaningful new logic, several files, edge cases. |
| **12**  | Two days — significant rework, multiple unknowns to resolve. |
| **18+** | Three days or more — flag that this rework probably should have been a fresh story. |

Take the **lower** of two adjacent rows for low-complexity rework — mechanical fixes, pure config, a pattern already used elsewhere in the file. Take the **higher** for high-complexity rework — ambiguous feedback, missing UX, data migrations, or regression risk in unrelated areas. Don't reach for the top of the ladder just because the round touches several files.

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

1. Call `mcp__azure-devops__wit_work_item_write` (action `create`):
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
     - `System.State` — `Active`, since the rework starts right now (fall back to the template's in-progress equivalent, or leave it at the default and note it). A rework Task left at `New` while the work is underway misreports the board.

2. Link the new Task as a child of the parent work item via `wit_work_item_link_write` (action `link`):
   - **type**: `Child` (the parent → child link from the parent's perspective; equivalent to `Parent` from the task's perspective)
   - **source**: parent work item ID
   - **target**: new task ID

3. Confirm to the user: `Created task AB#{taskId} (parent: AB#{id}, est: {hours}h)`.

If the user cancels, skip task creation and proceed — note "No rework task created" in the final summary.

## Step 6: Switch to Existing Branch

**In a worktree** (the default), there is nothing to switch. Step 0c has already put `WT` on the previous PR's branch and pulled it — or, if that PR merged and its branch was deleted, on a new branch from the PR's target. Confirm with `git -C "{WT}" status -sb` and go on to "Move the Work Item to Active".

**Working in place**, the work item already has a branch from the previous PR. Switch to it:

1. Get the source branch name from the most recent PR
2. Switch to that branch: `git checkout <branch-name>`
3. Pull the latest: `git pull`

If the PR was completed/merged and the branch was deleted, create a new branch from the PR's target branch following the same naming convention as `/implement` Step 4.

### Move the Work Item to Active

Once you are on the branch, move the work item (User Story, Bug, Hot Fix, or other single work item — **never** a Feature) to `Active` via `wit_work_item_write` (action `update`):
- **path**: `/fields/System.State`
- **value**: `Active`

Rework restarts implementation, so the item must leave `Code Review` / `Rework` and go back to in-progress for the duration of this round — Step 12 hands it back to `Code Review` when the fixes are pushed. Without this the item sits in a review state while it is actively being worked, and the board lies.

If the work item is already `Active`, skip the update. If the project's process template does not have an `Active` state (the update call returns an invalid-state error), fall back in this order: `In Progress` → `Doing` → leave the current state and warn the user that the state could not be advanced automatically. Do not silently swallow the error.

After the update, **read the work item back** (`wit_work_item`, action `get`) and confirm `System.State` actually changed. If it didn't, say so explicitly — do not proceed reporting the item as in progress when the board still shows it otherwise.

## Step 7: Implement

**In a worktree**, install frontend dependencies first — only if the approved plan touches the frontend. A new worktree has no `node_modules`, so run `npm install` in its client folder (`cd "{WT}/{client folder}" && npm install`). A backend-only plan skips the install; `dotnet build` restores its own packages. Steps 8–9 then skip the uninstalled client folder and report it as `frontend skipped — untouched by this rework, not installed in the worktree` rather than failing on it.

1. **Implement** the rework using backend and/or frontend agents according to the approved plan — each agent is told to work only in `WT` (Step 0e)
2. **Write the unit tests** listed in the plan's "Unit Tests" section alongside the implementation — not after. Include any regression test that would have caught the original issue
3. **Generate mockup** if there are UI changes

## Step 8: Build Validation

Run a build check **before** any other quality checks. Use the `build-validator` agent to verify that all projects compile successfully.

- If the build fails, **fix the errors immediately** and re-run until the build passes
- Do NOT proceed to review, tests, or lint until the build is clean

## Step 9: Quality Checks

1. **Run the full test suite** — every unit test in the repo, plus integration tests. Not just the tests added in this rework. A failure in an unrelated test means this rework broke something else; treat it as a regression, fix it, and re-run until the entire suite is green
2. **Run lint** — ESLint and dotnet format
3. **Environment configuration parity** — if the rework added or changed any key in `appsettings.*.json` or `.env*`, verify every parallel environment file (Development/Test/QA/Staging/Production for backend; `.env.development`/`.env.test`/`.env.staging`/`.env.production`/`.env.example` for React — whichever exist in the repo) has a corresponding entry. Present a (key × environment) table. Prompt the user to fill in any missing values (real, placeholder, or empty) **before pushing**, or to explicitly confirm the omission is intentional (e.g., supplied via a pipeline variable group, Key Vault, or App Configuration).
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

1. Push the changes: `git push` (in a worktree: `git -C "{WT}" push` — or `git -C "{WT}" push -u origin HEAD` when Step 0c created a new branch because the old one was deleted; it has no upstream yet)
2. **Do not post a rework summary comment.** Do not add a summary of what changed to the work item Discussion (`wit_work_item_comment_write` (action `add`)) or as a PR thread. The pushed commits and the PR diff are the record of what changed — a prose summary duplicates them and clutters the work item. If the reviewer left specific PR comment threads, reply on those threads directly (that is what `/resolve-feedback` and `/fix-review` do); otherwise post nothing.
3. **Attach deployment scripts.** Run `/implement`'s **Attaching Deployment Scripts** step against this branch — diff it against the PR's target branch (`git diff --name-only --diff-filter=AM {target}...HEAD`), so a script the original PR added and never attached is caught too. A script this rework changed is already attached in its old form: replace that attachment, don't add a second copy — a promotion that lists both versions invites someone to run the stale one. Same rules and report lines as in `/implement` (see **Deployment Scripts** in CLAUDE.md).
4. **Close related Tasks and log hours** — see "Closing Related Tasks" below. This includes the rework Task created in Step 5 as well as any other child Tasks that became `Completed` as a result of this rework round.
5. **Move the work item back to `Code Review`** via `wit_work_item_write` (action `update`):
   - **path**: `/fields/System.State`
   - **value**: `Code Review`

   Rework is triggered by reviewer feedback, so the item was likely in `Active` / `In Progress` / `Rework` while the fixes were being made. Pushing the rework hands it back to the reviewer, so it belongs in `Code Review` again.

   If the project's process template does not have a `Code Review` state (the update call returns an invalid-state error), fall back in this order: `Resolved` → `In Review` → leave the current state and warn the user. Do not silently swallow the error.
6. **Remove the ticket's worktree** — Step 13, once everything above is done.

> **PR completion closes the Task only.** When the PR is later completed/merged, only the child **Task** may be closed — never the parent User Story or Bug. Azure DevOps's "Complete associated work items" option transitions *every* linked work item (including the parent the PR is linked to), so do **not** enable it when completing the PR. Close the child Task explicitly instead; the parent stays in `Code Review` until it is promoted through `dev → test → staging → prod` (see **Work Item States ↔ Environments** in CLAUDE.md).

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

Once the user has answered, update each task via `wit_work_item_write` (action `update`):
- `Microsoft.VSTS.Scheduling.CompletedWork` → the agreed value
- `Microsoft.VSTS.Scheduling.RemainingWork` → `0`
- `System.State` → `Closed` (fall back to `Done` if the project's task template uses Agile; warn if neither is valid)

Confirm with a summary line per task: `Closed AB#xxxx — {hours}h logged`.

## Step 13: Remove the Ticket's Worktree

Skip this step when working in place.

This runs **last**: after the push and every Step 12 prompt, the Task-closing ones included, is answered. A failed push therefore never loses work, and the attachment and diff steps still have the worktree to read from. The branch is safe on origin now, and the next `/rework AB#{id}` recreates the worktree from it.

1. **Unlock it** — this session is done with it: `git -C "{MAIN}" worktree unlock "{WT}"`. Unlock even if step 3 ends up keeping it, so a later Step 0b can tidy it once it's clean, pushed, and merged.
2. **Check it's safe to remove:**

   ```bash
   git -C "{WT}" status --porcelain              # must print nothing
   git -C "{WT}" rev-list --count '@{u}..HEAD'   # must print 0
   ```
3. **Both pass** → remove the worktree, then the local branch:

   ```bash
   git -C "{MAIN}" worktree remove "{WT}"
   git -C "{MAIN}" branch -D "{branch}"
   ```

   Report: `Removed {WT} and local branch {branch} — the branch is on origin; /rework AB#{id} brings it back.`

   **Either fails** → keep it, and say exactly what's left: the `git -C "{WT}" status --short` lines, or the unpushed commits (`git -C "{WT}" log --oneline '@{u}..HEAD'`). **Never `--force`, never `rm` the folder.**
4. **Never remove a worktree the session is standing in.**
   - If the folder this session started in is `WT` or inside it, don't remove it — that would pull the folder out from under the session. Print the command for the user to run from another folder instead: `git -C "{MAIN}" worktree remove "{WT}" && git -C "{MAIN}" branch -D "{branch}"`.
   - If `WT` is `MAIN` (Step 0c reused a branch already checked out there), there is nothing to remove.
