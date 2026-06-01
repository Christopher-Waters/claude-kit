Resolve unresolved comment threads on a pull request. Usage: `/resolve-feedback <pr-id>` (or `/resolve-feedback` to auto-detect from the current branch).

This is the lightweight counterpart to `/rework`. It targets **PR comment threads** specifically — read each active thread, implement the fix, push, then reply to and resolve the thread on the PR. No Task creation, no hours tracking, no UAT gate. Use `/rework` when feedback spans the whole work item or requires a new round of full quality checks.

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

## Step 2: List Active Comment Threads

Call `repo_list_pull_request_threads` for the PR. Filter the returned threads to the ones that need a response:

**Include a thread when all of these are true:**
- `status` is `active` or `pending` (statuses `1` or `6`). Skip `fixed`, `wontFix`, `closed`, `byDesign`.
- It contains at least one comment authored by a real reviewer (`commentType` is `text`, not `system`).
- It is not a system-generated thread (vote changes, policy violations, build failures, work-item link additions, etc. — these have `commentType: system` or no real comments).
- It is not authored exclusively by the current PR author. A thread where the PR author is talking to themselves with no reviewer input is not feedback to resolve. (Use the PR `createdBy.id` as the author id.)

For each remaining thread, capture:
- `threadId`
- `threadContext` — `filePath`, `rightFileStart.line` / `leftFileStart.line` (may be null for PR-level threads)
- Full comment chain via `repo_list_pull_request_thread_comments` — author, date, body. Inline images in comments often carry critical context; if a comment body contains an `<img src="...">` pointing to an Azure DevOps attachment, download and view it via WebFetch before proposing a fix.

If there are zero qualifying threads, tell the user `No unresolved reviewer threads on PR #{id}.` and stop.

## Step 3: Switch to the PR Branch

Before reading code or proposing fixes, make sure local state matches the PR:

1. `git fetch`
2. If the current branch ≠ `sourceRefName` (stripping `refs/heads/`): `git checkout <source-branch>`. If the branch does not exist locally, `git checkout -b <source-branch> origin/<source-branch>`.
3. `git pull --ff-only` — refuse to proceed on a dirty or diverged working tree; ask the user to resolve it first rather than auto-stashing or force-resetting.

## Step 4: Triage and Propose Responses

For each qualifying thread, read the referenced code (use `threadContext.filePath` + line) and decide one of:

- **fix** — code change needed. Draft the change in your head and capture which files will be touched.
- **reply-only** — answers the reviewer's question without a code change (clarification, link to existing code, explanation of intentional design). Capture the reply text.
- **defer** — out of scope for this round; reply explaining why and leave the thread `active`. Do not silently skip.

Present the full triage to the user before touching any code:

```
PR #{id}: {title}
Branch: {source-branch} → {target-branch}
Active reviewer threads: {count}

## Thread 1 — {file}:{line}  (or "PR-level" if no file context)
Reviewer ({name}, {date}):
> {comment excerpt — first ~200 chars}
{additional reply chain summarized in 1 line each, if any}

Proposed action: FIX
Files to change:
  - {path} — {what changes}
  - {path} — {what changes}
Reply on resolve: "{short summary that will be posted with the resolution}"

## Thread 2 — {file}:{line}
Reviewer ({name}, {date}):
> {comment excerpt}

Proposed action: REPLY-ONLY (no code change)
Reply: "{text to post}"

## Thread 3 — PR-level
Reviewer ({name}, {date}):
> {comment excerpt}

Proposed action: DEFER (out of scope for this round)
Reply: "{text explaining why this will be handled separately}"

---
Approve this plan? (yes / edit <n>: <change> / skip <n> / no)
```

**Wait for the user's response.** Apply edits and re-present until the user replies `yes`. `skip <n>` removes a thread from this round entirely — it stays active on the PR and gets no reply.

## Step 5: Implement the Fixes

For each thread marked **fix** in the approved plan:

1. Make the code change. Use the `backend` / `frontend` / `legacy` agents when the change is non-trivial; small targeted edits can go through `Edit` directly.
2. Add or update tests when the fix changes observable behavior. A reviewer comment that says "this doesn't handle empty input" implies a missing test case — add it. Do not add tests for pure rename/comment/formatting fixes.

Implement all fixes before moving to validation — batching keeps the build/test cycle short.

## Step 6: Validate

Run in this order. Stop and fix on the first failure before continuing.

1. **Build** — via the `build-validator` agent. Build must be clean.
2. **Lint** — `dotnet format` for `.cs` changes, ESLint for `.ts`/`.tsx` changes (only on touched files; full-repo lint runs are wasteful here).
3. **Tests** — run the test suites that cover the files you touched (`test-runner` agent). If a touched file has no test coverage, call that out in the final summary rather than silently skipping.

If validation fails after a reasonable fix attempt, stop and report — do not push broken code to resolve a comment.

## Step 7: Confirm Before Pushing

Show the user exactly what will happen next:

```
Validation passed.

Changes ready to push to {source-branch}:
{git diff --stat output}

About to:
  1. git push origin {source-branch}
  2. For each FIX thread:   reply with the resolution summary + mark as Fixed (status 2)
  3. For each REPLY-ONLY:    reply with the response + mark as Closed (status 4)
  4. For each DEFER thread:  reply with the deferral note + leave status Active

Proceed? (yes / no)
```

**Wait for `yes`.** Anything else aborts without pushing or touching the PR.

## Step 8: Push and Update the PR

1. `git push origin <source-branch>`.
2. For each thread in the approved plan, in order:
   - Call `repo_reply_to_comment` with the reply text. Reference the new commit SHA in FIX replies (e.g. `Fixed in {sha} — {one-line summary of what changed}`).
   - Call `repo_update_pull_request_thread` to set `status`:
     - **fix** → `fixed` (2)
     - **reply-only** → `closed` (4)
     - **defer** → leave as `active` (do not call the update; only the reply was posted)
3. After every thread has been processed, post one PR-level summary comment via `repo_create_pull_request_thread` (new top-level thread, status `closed`):

   ```
   Resolved review feedback in {sha}:
   - {N} threads addressed with code fixes
   - {M} threads answered without code changes
   - {K} threads deferred ({reason summary})
   ```

   Skip the summary comment if only one thread was touched — the reply on that thread already says everything.

4. Do **not** change the work item state, do **not** create Tasks, do **not** log hours. Those belong to `/rework`. Leave the PR vote alone — the reviewer drives the next vote when they see the resolved threads.

## Step 9: Final Report

Print to the user:

```
PR #{id} — feedback resolved
  Branch:       {source-branch} ({sha})
  Fixed:        {N} thread(s)
  Replied:      {M} thread(s)
  Deferred:     {K} thread(s)
  Files touched: {file count}
  Tests added/updated: {test file count, or "none — no behavior change"}
```

If any thread was deferred, list those thread ids explicitly so the user can decide whether they need to file a follow-up work item or address them in a later round.
