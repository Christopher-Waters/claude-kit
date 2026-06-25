Deeply review PR #$ARGUMENTS in the current project — a local, checkout-based, Ultracode-orchestrated version of `/review`. Does everything `/review` does, plus: checks out the branch, verifies every requirement is implemented, confirms nothing else broke, and flags any changes the developer made that fall outside the work item. Follow this workflow:

## Always Use Ultracode

This command **always orchestrates its analysis-heavy phases with the `Workflow` tool** — you do not wait to be asked, and you do not need the `ultracode` keyword. The slash command runs in the main loop, which has the `Workflow` tool, so fan-out is available throughout. This is the deep-review counterpart to `/review`: where `/review` reads the PR diff over MCP, `/deep-review` checks the branch out locally and runs a far more exhaustive, multi-agent analysis.

What this means in practice:

- **Fan out the read / analyze / verify work** — rework-context detection (Step 2), per-acceptance-criterion coverage (Step 5), regression analysis (Step 6), scope/unwanted-change detection (Step 7), and the review dimensions (Step 8) are run as `Workflow` scripts with one agent per independent unit (per prior PR, per acceptance criterion, per impacted subsystem, per review dimension). Each agent returns **structured findings** via a `schema`; you synthesize the results in the main loop.
- **Never fan out an interactive gate, a write, or a vote.** Every user prompt (Steps 7, 9, 10) and every PR mutation — posting comments, voting (Steps 10–11) — stays in the **main loop**. Workflow agents here are **read-only analysts** — they use MCP read tools, `Read`, `Grep`, and `Bash` for read-only inspection (builds, tests, `git diff`), and they return data. They do not post comments, vote, switch branches, write code, or ask the user anything.
- **Stay in the loop between phases.** Run one `Workflow` per phase, read its results, present/await the user as the steps require, then launch the next phase's workflow. This is several short workflows in sequence — not one monolithic run that tries to swallow the approval gates.
- **Review uses the canonical find → adversarially-verify pipeline** (Step 8): fan out per dimension, then spawn skeptic verifiers per finding and drop findings the majority refute, so only confirmed issues reach the user. Use the `reviewer` agent type for the dimension agents (`agentType: 'reviewer'`) so they inherit its review rules.

If the `Workflow` tool is somehow unavailable, fall back to running each phase sequentially in the main loop — the output is identical, just slower.

## Step 1: Resolve the PR, Work Item, and Branch

Handle `$ARGUMENTS` as a PR id (e.g. `142`).

1. **Read the PR** via `repo_get_pull_request_by_id` — capture the **source branch**, **target branch**, title, description, and status.
2. **Read the linked work item** and gather the full description and acceptance criteria. Download and view every embedded image in the description / acceptance criteria via `WebFetch` — visual requirements (mockups, expected UI, error states) are part of the spec and you cannot verify "implemented properly" without seeing them.
3. **Read the full diff** via `repo_get_pull_request_changes` — understand every file the PR touches. This is the canonical list of what the developer changed.

## Step 2: Check Out the Branch Locally

Unlike `/review`, this command works against the real working tree so it can build, test, and inspect the full code — not just the diff hunks.

1. Stash or confirm a clean working tree first. If the working tree is dirty, **stop and tell the user** — do not stash their work without asking.
2. `git fetch` then `git checkout <source-branch>` and `git pull` to get the exact code under review.
3. Compute the review diff range against the target branch: `git merge-base <target-branch> HEAD` → use `git diff <merge-base>..HEAD` as the authoritative diff for all later steps. This is more reliable than the MCP diff for local analysis and matches what will actually merge.
4. Confirm to the user which branch and commit you are reviewing:

   ```
   Reviewing PR #{id} — {title}
     Source branch: {source}  @ {short-sha}
     Target branch: {target}
     Work item:     AB#{wi} — {wi title}
     Files changed: {n}
   ```

If checkout fails (branch deleted after merge, etc.), tell the user and offer to fall back to a diff-only review (the `/review` behavior) instead.

## Step 3: Detect Rework Context — do this BEFORE judging acceptance criteria

A small diff does not mean a small feature. The PR you are reviewing may be a rework that only addresses targeted feedback, while the bulk of the implementation already shipped in earlier PRs. Judging acceptance criteria against the current diff alone will produce false "not met" findings.

> **Ultracode:** Fan out with `Workflow` — one agent per PR linked to the work item, each fetching its details and classifying it. Synthesize in the main loop.

For each PR linked to the work item (via `relations` / artifact links), fetch its details and classify:
- **This PR** — the one being reviewed.
- **Prior merged PRs** — `status: completed` and merged before this PR was created. Their changes are already in the target branch.
- **Prior abandoned PRs** — ignore for acceptance-criteria coverage; their code is not in the target branch.

Also scan the work item comments for rework feedback posted after the most recent prior merged PR. That feedback is what the current PR is expected to address.

Treat the PR as a **rework** if any prior merged PR exists for this work item, OR if the work item has rework feedback comments dated after a prior PR. Otherwise treat it as an **initial PR**.

## Step 4: Build and Test the Checked-Out Branch

Because the branch is local, prove it actually works before judging it — a PR that does not build or whose tests fail is not mergeable regardless of how the code reads.

1. **Build** every affected project with the `build-validator` agent. Record pass/fail and any errors.
2. **Run the full test suite** with the `test-runner` agent — every unit test in the repo, plus integration tests, not just tests touched by this PR. A failure in an unrelated test is a regression signal for Step 6.
3. **Run lint** — ESLint and `dotnet format` via the `lint-checker` agent.

Capture the results; do not fix anything (this command is read-only on the code). Build/test/lint failures become findings in the Step 8 summary, flagged **critical**.

## Step 5: Verify Every Requirement Is Implemented — Deep AC Coverage

This is the core of `/deep-review`: confirm **nothing in the spec was missed** and everything was **implemented properly**, not just superficially present.

> **Ultracode:** Fan out with `Workflow` — **one agent per acceptance criterion**. Each agent reads the relevant code in the checked-out tree and returns `{ac, status, evidence, gaps}` where:
> - `status` ∈ `met-this-pr` | `met-prior-pr` | `partial` | `not-met` | `not-applicable`
> - `evidence` — the specific file(s)/line(s) and test(s) that prove the AC is satisfied
> - `gaps` — anything required by the AC (including details only visible in the embedded images) that is missing, stubbed, or only partially done
>
> Evaluate coverage against the **cumulative work**, not just this diff:
> - **Initial PR**: every AC must be satisfied by this PR's diff.
> - **Rework PR**: an AC may be satisfied by (prior merged PRs already in the target branch) + (this PR's diff). Mark those `met-prior-pr` — do not flag them as missing — but re-check any AC whose area this PR's diff touches, for regression.
>
> Collect all results in the main loop. Any `partial` or `not-met` AC is a blocking finding.

For a rework PR with a small diff, also ask the focused question: **does this diff correctly address the rework feedback, and does it avoid regressing the prior implementation?** — not "does this diff implement every AC from scratch?"

## Step 6: Confirm It Didn't Break Other Code — Regression Analysis

Verify the change is safe beyond the lines it touched.

> **Ultracode:** Fan out with `Workflow` — one agent per subsystem or shared component the diff could affect (callers of changed methods, shared DTOs/interfaces, database schema or query shape changes, public API contracts, config/env changes). Each agent returns `{area, impact, risk, evidence}`. Seed the agents with: (a) the full-suite test results from Step 4, (b) the list of changed symbols, and (c) `grep` for usages of every changed public symbol. Synthesize a regression risk table in the main loop.

Specifically check:
- **Changed shared code** — for every public method/class/interface/DTO the diff modifies, find its other callers and confirm the change is backward-compatible or all callers were updated.
- **Test fallout** — any failing test from Step 4 in an area this PR didn't intend to change is a regression; surface it as **critical**.
- **Environment configuration parity** — if the diff adds or changes any key in `appsettings.*.json` or `.env*`, every parallel environment file (Development/Staging/QA/Production for backend; `.env.development`/`.env.staging`/`.env.production`/`.env.example` for React) must have a corresponding entry, or the omission must be called out. Build a (key × environment) table and flag any missing cell as **critical**. A pipeline variable group, Key Vault, or App Configuration counts as a valid source for an environment — verify it exists rather than assume it.

## Step 7: Detect Unwanted / Out-of-Scope Changes — and Confirm With the User

The developer should have changed **only** what the work item requires. Catch anything extra — accidental commits, debug code, unrelated refactors, formatting churn, vendored files, secrets, commented-out blocks, or scope creep.

> **Ultracode:** Fan out with `Workflow` — one agent per changed file (or per logical group of files). Each agent answers: *does this change map to an acceptance criterion or the work item's stated intent?* and returns `{file, mapsToAC, classification, rationale}` where `classification` ∈ `in-scope` | `incidental-ok` (e.g. an unavoidable import or a generated file) | `out-of-scope` | `suspicious` (debug code, leftover TODO, commented-out blocks, stray console/Debug logging, unrelated dependency bumps, large reformat-only diffs). Synthesize in the main loop into a single scope table.

Present every out-of-scope or suspicious change to the user and **wait for a decision** — do not silently fold these into the review:

```
## Out-of-Scope / Unexpected Changes in PR #{id}

These changes do not map to any acceptance criterion on AB#{wi}:

| # | File | What changed | Why it looks out of scope |
|---|------|--------------|---------------------------|
| 1 | {file} | {summary} | {e.g. unrelated refactor of an untouched module} |
| 2 | {file} | {summary} | {e.g. leftover console.log / commented-out code} |
| 3 | {file} | {summary} | {e.g. dependency bump unrelated to this work item} |

For each, tell me how to treat it:
- "ok 1,3"        → accepted as intentional; I won't flag them
- "flag 2"        → I'll raise it as a review finding (severity I'll pick by type)
- "ok all" / "flag all"
```

**Wait for the user's response.** Items the user marks `ok` are dropped from the findings. Items marked `flag` (or anything genuinely dangerous — a committed secret, disabled security check, or `.env` with real values — which you should flag as **critical** regardless of the user's call, while telling them why) carry into the Step 8 review summary. If there are no out-of-scope or suspicious changes, state that and skip the prompt.

## Step 8: Review for Quality — find → adversarially-verify

> **Ultracode:** Run the review as a `Workflow` find → verify pipeline. **Find:** fan out one agent per dimension (below), each scoped to the Step 2 diff range and returning structured findings. **Verify:** for each finding, spawn independent skeptic agents prompted to *refute* it (default to refuted if uncertain); drop any finding the majority refute. Only confirmed findings reach the user. Use `agentType: 'reviewer'` for the dimension agents.

Review dimensions:
- Clean Architecture boundaries (Domain has no infrastructure dependencies)
- Tenant/`organizationId` enforcement on all database queries
- Missing unit or integration tests for new code
- `any` types in TypeScript (should be properly typed)
- Security issues (OWASP Top 10, hardcoded secrets, SQL/NoSQL injection, exposed PII)
- Error handling (are exceptions caught appropriately?)
- Naming conventions and code style consistency
- Breaking changes or backwards compatibility issues (cross-reference Step 6)
- **CLAUDE.md compliance** — sensitive-data rules, work-item prefix conventions, branching, anything the project's CLAUDE.md mandates

Fold in the carried-over findings from Steps 4 (build/test/lint), 5 (AC gaps), 6 (regressions, env parity), and 7 (flagged out-of-scope changes).

## Step 9: Draft the Comments and Summary

**Draft (do not post yet) the inline comments** for every confirmed finding. For each, capture: file path, line number, severity, and the exact comment body.

**Draft (do not post yet) the PR-level summary comment** with:
- **PR type**: Initial PR or Rework (and if rework, the prior merged PR numbers and the rework feedback addressed)
- **Build / Test / Lint**: pass/fail from Step 4
- Overall assessment (ready to merge / needs changes)
- Count of issues by severity (critical / warning / suggestion)
- **Acceptance criteria checklist** — each item marked `met (this PR)` / `met (prior PR #N)` / `partial` / `not met` / `not applicable`, with the evidence or gap from Step 5
- **Regression assessment** — from Step 6 (impacted areas + result)
- **Out-of-scope changes** — what was found and how it was dispositioned in Step 7
- **Rework feedback checklist** (rework PRs only) — each item addressed / not addressed
- Test coverage assessment

## Step 10: Preview Everything and Wait for Approval

**Preview every comment to me and wait for approval before posting anything to the PR.** Show:

```
Deep review drafted — nothing has been posted to PR #{id} yet.

## Inline comments ({count})
1. {file}:{line} [{severity}] — {comment body}
2. ...

## PR summary comment
{full summary body as it will appear on the PR}

Reply with one of:
- "approve" → post all inline comments and the summary exactly as shown above
- "skip"    → post nothing
- "edit <number>: <new text>" or "skip <numbers>" → revise/drop specific items, then I'll re-preview before posting
```

**Wait for my response. Never post any comment to the PR until I reply "approve".** If I edit or skip individual items, apply the changes and re-preview the full set before asking again. "skip" with no numbers means post nothing at all — move directly to Step 11 without posting.

## Step 11: Post and Vote

If I approved, post the inline comments and the summary to the PR. If I skipped, post nothing. Either way, then ask me:

```
{Comments posted to PR #{id}. | No comments posted (skipped).}
- PR type: {Initial | Rework of prior PR(s) #N, #M}
- Build/Test/Lint: {pass | fail — detail}
- X critical issues
- Y warnings
- Z suggestions
- Acceptance criteria: A met this PR, B met in prior PRs, C partial, D not met
- Regressions: {none | detail}
- Out-of-scope changes: {none | E accepted, F flagged}
- Rework feedback (if rework): G/H addressed

Approve, Request Changes, or skip the vote?
```

Wait for my response before submitting any vote on the PR. Then restore the user's original branch if you switched away from it in Step 2 (tell them before doing so).
