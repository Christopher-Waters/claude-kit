Review PR #$ARGUMENTS in the current project. Automatically:

1. **Read the full diff** — understand every change in the PR.

2. **Read the linked work item** and gather the full acceptance criteria.

   **Effort gate — do this before the review reasoning (steps 3+).** Reasoning effort is a harness setting the user controls; this command cannot change it. Recommend a level based on the diff you just read, then let the user set it. Rubric (the session default is usually `high`):

   | Effort | When |
   |--------|------|
   | `medium` | Small diff — a few files, mechanical or well-scoped change, short AC list. |
   | `high` | Standard PR — cross-layer diff, a handful of files, a normal AC set. Recommend this unless clearly lighter or heavier. |
   | `xhigh` | Large or subtle diff — many files/subsystems, many acceptance criteria, security-sensitive or concurrency-heavy code. |
   | `max` | Exceptional: security-critical or architecturally risky change where you want maximum scrutiny. Session-only. |

   Signals: files changed, additions/deletions, acceptance-criteria count, and whether the diff touches security- or data-integrity-sensitive code. Present:

   ```
   Suggested reasoning effort for this review: **{level}** — {one-line justification}.
   Effort is set by you, not me. Run `/effort` to adjust if needed, then reply **ready** —
   or reply **go** to review at your current level.
   ```

   **Wait for `ready` or `go` before continuing.** Never try to set the effort level yourself; only recommend it.

3. **Detect rework context — do this BEFORE judging acceptance criteria.**

   A small diff does not mean a small feature. The PR you are reviewing may be a rework that only addresses targeted feedback, while the bulk of the implementation already shipped in earlier PRs. Judging acceptance criteria against the current diff alone will produce false "not met" findings.

   For each PR linked to the work item (via `relations` / artifact links), fetch its details and classify:
   - **This PR** — the one being reviewed.
   - **Prior merged PRs** — `status: completed` and merged before this PR was created. Their changes are already in the target branch.
   - **Prior abandoned PRs** — ignore for acceptance-criteria coverage; their code is not in the target branch.

   Also scan the work item comments for rework feedback posted after the most recent prior merged PR. That feedback is what the current PR is expected to address.

   Treat the PR as a **rework** if any prior merged PR exists for this work item, OR if the work item has rework feedback comments dated after a prior PR. Otherwise treat it as an **initial PR**.

4. **Evaluate acceptance criteria against the cumulative work, not just this diff.**

   - **Initial PR**: evaluate every acceptance criterion against this PR's diff.
   - **Rework PR**: evaluate every acceptance criterion against (prior merged PRs' changes already in the target branch) + (this PR's diff). For criteria already satisfied by prior merged PRs, do not flag them as missing — mark them as **previously delivered** and only re-check them if this PR's diff touches the same area in a way that could regress the prior implementation.

   When a rework PR's diff is small, the right question is **"does this diff correctly address the rework feedback, and does it avoid regressing the prior implementation?"** — not "does this diff implement every acceptance criterion from scratch?"

5. **Review for:**
   - Clean Architecture boundaries (Domain has no infrastructure dependencies)
   - Tenant/organizationId enforcement on all database queries
   - Missing unit or integration tests for new code
   - `any` types in TypeScript (should be properly typed)
   - Security issues (OWASP Top 10, hardcoded secrets, SQL/NoSQL injection)
   - Error handling (are exceptions caught appropriately?)
   - Naming conventions and code style consistency
   - Breaking changes or backwards compatibility issues
   - **Environment configuration parity** — if the diff adds or changes any key in `appsettings.*.json` or `.env*`, every parallel environment file (Development/Test/QA/Staging/Production for backend; `.env.development`/`.env.test`/`.env.staging`/`.env.production`/`.env.example` for React) must have a corresponding entry, or the omission must be called out in the PR description. Build a table of (key × environment) and flag any missing cell as **critical**. Pipeline variable groups, Key Vault, or App Configuration wiring counts as a valid source for a given environment — verify it exists rather than assume it.
   - **Rework-specific (if applicable):** does this diff fully address every item in the rework feedback? Does it regress anything that prior merged PRs delivered?

6. **Draft (do not post yet) the inline comments** for every finding. For each, capture: file path, line number, severity, and the exact comment body you intend to post.

7. **Draft (do not post yet) the PR-level summary comment** with:
   - **PR type**: Initial PR or Rework (and if rework, list the prior merged PR numbers and the rework feedback being addressed)
   - Overall assessment (ready to merge / needs changes)
   - Count of issues by severity (critical / warning / suggestion)
   - **Acceptance criteria checklist**, with each item marked as one of:
     - **met (this PR)** — satisfied by changes in this diff
     - **met (prior PR #N)** — already delivered in a prior merged PR; not in this diff
     - **not met** — not satisfied by any merged or pending change
     - **not applicable** — out of scope for this work item
   - **Rework feedback checklist** (rework PRs only) — each feedback item marked addressed / not addressed
   - Test coverage assessment

8. **Preview every comment to me and wait for approval before posting anything to the PR.** Show:

   ```
   Review drafted — nothing has been posted to PR #{id} yet.

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

   **Wait for my response. Never post any comment to the PR until I reply "approve".** If I edit or skip individual items, apply the changes and re-preview the full set before asking again. "skip" with no numbers means post nothing at all — move directly to step 9 without posting.

9. If I approved, post the inline comments and the summary to the PR. If I skipped, post nothing. Either way, then ask me:
```
{Comments posted to PR #{id}. | No comments posted (skipped).}
- PR type: {Initial | Rework of prior PR(s) #N, #M}
- X critical issues
- Y warnings
- Z suggestions
- Acceptance criteria: A met this PR, B met in prior PRs, C not met
- Rework feedback (if rework): D/E addressed

Approve, Request Changes, or skip the vote?
```

Wait for my response before submitting any vote on the PR.
