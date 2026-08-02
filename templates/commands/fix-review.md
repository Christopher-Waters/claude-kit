Fix everything flagged on a pull request. Usage: `/fix-review <pr-id>` (or `/fix-review` to auto-detect from the current branch).

This command fixes **anything a reviewer raised on the PR** — whether the reviewer is a person leaving inline comments or the automated `/review` / `/deep-review` pass that posts severity-tagged findings. It reads every open comment, plans a concrete fix for each, validates, pushes, and resolves the threads. The default disposition is **fix it** — if the reviewer flagged something, you make the change.

**How this differs from `/resolve-feedback`:** `/resolve-feedback` is triage-oriented — it weighs each thread as fix / reply-only / defer and is built for back-and-forth conversation with a reviewer. `/fix-review` is fix-oriented — its job is to burn down the whole list of flagged items and get the PR mergeable, defaulting every flagged item to a code fix unless it's genuinely wrong or out of scope. Use `/resolve-feedback` when you mostly want to *discuss* the feedback; use `/fix-review` when you want to *clear* it. Neither touches work-item state, hours, or UAT — that's `/rework`.

## Step 1: Identify the Pull Request

Parse `$ARGUMENTS`:

- **PR id given** (`142`, `#142`, `!142`) — strip non-digits and use as the PR id.
- **No argument** — find the PR for the current branch:
  1. Get current branch via `git rev-parse --abbrev-ref HEAD`.
  2. Call `repo_list_pull_requests_by_repo_or_project` filtered to `sourceRefName: refs/heads/<branch>` and `status: active`.
  3. If exactly one match, use it. If zero or multiple, ask the user which PR id to target — do not guess.

Fetch the PR via `repo_get_pull_request_by_id`. Record:
- `pullRequestId`, `title`, `status`
- `sourceRefName` (the branch holding the fixes) and `targetRefName`
- Linked work item id(s) from artifact links — used only for context, not modified by this command.

## Step 2: Collect Everything Flagged

Call `repo_list_pull_request_threads` for the PR, then read each thread's comments via `repo_list_pull_request_thread_comments`. Gather **every open thing a reviewer raised** — both human reviewer comments and automated `/review` / `/deep-review` findings.

**Include a thread when all of these are true:**
- `status` is `active` or `pending` (statuses `1` or `6`). Skip `fixed`, `wontFix`, `closed`, `byDesign` — those are already handled.
- It contains at least one real reviewer comment (`commentType: text`), not a system thread (vote changes, build status, policy violations, work-item link additions — these are `commentType: system`).
- It is not authored exclusively by the PR author talking to themselves with no reviewer or automated-review input. Use the PR `createdBy.id` to identify the author.

This captures both sources:
- **Human reviewer comments** — free-form prose, often without a severity tag. Infer severity from the language ("this will crash" → critical; "consider renaming" → suggestion); when unclear, default to **warning**.
- **Automated review findings** — `/review` / `/deep-review` post inline comments in the form `{file}:{line} [{severity}] — {body}` plus a PR-level summary comment with "X critical / Y warnings / Z suggestions" and an acceptance-criteria checklist. Read that summary comment too, and use it to recover any finding raised only in the summary, not as an inline comment.

For each flagged item, capture:
- `threadId`
- **source** — human reviewer vs. automated review (so the reply can be worded appropriately)
- **severity** — critical / warning / suggestion (inferred for human comments as above)
- `threadContext` — `filePath`, `rightFileStart.line` / `leftFileStart.line` (may be null for PR-level threads)
- the comment body — what's wrong and any suggested fix. If a comment body contains an `<img src="...">` pointing to an Azure DevOps attachment, download and view it via WebFetch before proposing a fix — reviewers often paste screenshots that carry the real context.

If there are zero qualifying threads, tell the user `No open reviewer feedback on PR #{id}.` and stop.

### Effort gate — before planning and applying fixes (Steps 4–5)

Reasoning effort is a harness setting the user controls; this command cannot change it. Recommend a level based on the flagged items you just collected, then let the user set it. Rubric (the session default is usually `high`):

| Effort | When |
|--------|------|
| `medium` | A short list of low-severity, mechanical fixes (renames, nits, one or two obvious changes). |
| `high` | The common case — a mix of warnings and a few criticals across several files. Recommend this unless clearly lighter or heavier. |
| `xhigh` | Many findings, multiple critical issues, or fixes that touch subtle logic / span subsystems and risk regressions. |
| `max` | Exceptional: a critical finding that requires a genuine rethink or security-critical fix. Session-only. |

Signals: total flagged-item count and the severity mix (how many critical), plus whether the fixes concentrate in tricky code. Present:

```
Suggested reasoning effort for these fixes: **{level}** — {one-line justification citing the counts}.
Effort is set by you, not me. Run `/effort` to adjust if needed, then reply **ready** —
or reply **go** to proceed at your current level.
```

**Wait for `ready` or `go` before switching branches and planning.** Never try to set the effort level yourself; only recommend it.

## Step 3: Switch to the PR Branch

Before reading code or proposing fixes, make sure local state matches the PR:

1. `git fetch`
2. If the current branch ≠ `sourceRefName` (stripping `refs/heads/`): `git checkout <source-branch>`. If the branch does not exist locally, `git checkout -b <source-branch> origin/<source-branch>`.
3. `git pull --ff-only` — refuse to proceed on a dirty or diverged working tree; ask the user to resolve it first rather than auto-stashing or force-resetting.

## Step 4: Plan the Fixes

Order the items by severity — **critical first, then warning, then suggestion**. For each, read the referenced code (use `threadContext.filePath` + line, or locate it from the comment body for PR-level threads) and decide one of — **defaulting to fix**, because the point of this command is to clear what reviewers flagged:

- **fix** (the default) — apply the change the reviewer asked for. Capture which files will be touched and a one-line description of the change. Reach for this for anything actionable, whether it came from a person or the automated review.
- **disagree** — the comment is wrong or already addressed in the current code. Do not silently skip; capture a short rebuttal to post as a reply, and leave the thread for the reviewer to adjudicate. Use sparingly — a human reviewer flagged it for a reason, so only disagree when you're confident.
- **defer** — valid but genuinely out of scope for this round (e.g. a large refactor a suggestion asks for). Capture why; reply and leave the thread active.

Present the full plan to the user before touching any code:

```
PR #{id}: {title}
Branch: {source-branch} → {target-branch}
Flagged items: {count}  ({n} critical, {m} warning, {k} suggestion)

## Item 1 — [CRITICAL] {file}:{line}  (or "PR-level" if no file context)
Flagged by: {reviewer name | automated review}
> {comment excerpt — first ~200 chars}

Proposed action: FIX
Files to change:
  - {path} — {what changes}
Reply on resolve: "{short summary that will be posted with the resolution}"

## Item 2 — [WARNING] {file}:{line}
Flagged by: {reviewer name}
> {comment excerpt}

Proposed action: DISAGREE (already handled / incorrect)
Reply: "{rebuttal text}"

## Item 3 — [SUGGESTION] {file}:{line}
Flagged by: {automated review}
> {comment excerpt}

Proposed action: DEFER (out of scope for this round)
Reply: "{text explaining why this will be handled separately}"

---
Approve this plan? (yes / edit <n>: <change> / skip <n> / no)
```

**Wait for the user's response.** Apply edits and re-present until the user replies `yes`. `skip <n>` removes an item from this round entirely — it stays active on the PR and gets no reply.

## Step 5: Implement the Fixes

For each finding marked **fix** in the approved plan, in severity order:

1. Make the code change. Use the `backend` / `frontend` / `legacy` agents when the change is non-trivial; small targeted edits can go through `Edit` directly.
2. Add or update tests when the fix changes observable behavior. A finding that says "this doesn't handle empty input" implies a missing test case — add it. Do not add tests for pure rename/comment/formatting fixes.

Implement all fixes before moving to validation — batching keeps the build/test cycle short.

## Step 6: Validate

Run in this order. Stop and fix on the first failure before continuing.

1. **Build** — via the `build-validator` agent. Build must be clean.
2. **Lint** — `dotnet format` for `.cs` changes, ESLint for `.ts`/`.tsx` changes (only on touched files; full-repo lint runs are wasteful here).
3. **Tests** — run the test suites that cover the files you touched (`test-runner` agent). If a touched file has no test coverage, call that out in the final summary rather than silently skipping.

If validation fails after a reasonable fix attempt, stop and report — do not push broken code to clear a finding.

## Step 7: Confirm Before Pushing

Show the user exactly what will happen next:

```
Validation passed.

Changes ready to push to {source-branch}:
{git diff --stat output}

About to:
  1. git push origin {source-branch}
  2. For each FIX finding:       reply with the resolution summary + mark as Fixed (status 2)
  3. For each DISAGREE finding:  reply with the rebuttal + leave status Active
  4. For each DEFER finding:     reply with the deferral note + leave status Active

Proceed? (yes / no)
```

**Wait for `yes`.** Anything else aborts without pushing or touching the PR.

## Step 8: Push and Update the PR

1. `git push origin <source-branch>`.
2. For each finding in the approved plan, in order:
   - Call `repo_reply_to_comment` with the reply text. Reference the new commit SHA in FIX replies (e.g. `Fixed in {sha} — {one-line summary of what changed}`).
   - Call `repo_update_pull_request_thread` to set `status`:
     - **fix** → `fixed` (2)
     - **disagree** → leave as `active` (only the reply was posted — the user/reviewer adjudicates)
     - **defer** → leave as `active`
3. After every finding has been processed, post one PR-level summary comment via `repo_create_pull_request_thread` (new top-level thread, status `closed`):

   ```
   Addressed reviewer feedback in {sha}:
   - {N} fixed ({critical/warning/suggestion breakdown})
   - {D} disagreed (left active for adjudication)
   - {K} deferred ({reason summary})
   ```

   Skip the summary comment if only one finding was touched — the reply on that thread already says everything.

4. Do **not** change the work item state, do **not** create Tasks, do **not** log hours, do **not** vote on the PR. Those belong to `/rework` and to the reviewer.

## Step 9: Final Report

Print to the user:

```
PR #{id} — reviewer feedback addressed
  Branch:        {source-branch} ({sha})
  Fixed:         {N} finding(s)  ({n} critical, {m} warning, {k} suggestion)
  Disagreed:     {D} finding(s)
  Deferred:      {K} finding(s)
  Files touched: {file count}
  Tests added/updated: {test file count, or "none — no behavior change"}
```

If any finding was disagreed or deferred, list those thread ids explicitly so the user can adjudicate or file a follow-up. If any critical finding remains unfixed for any reason, call that out prominently — a PR with open critical findings should not merge.
