# Changelog

## 2.3.0 — 2026-09-29

### `/implement` and `/rework` work in their own git worktree per ticket

Several Claude Code sessions on the same repo no longer clobber each other's working tree. Each ticket gets a sibling worktree, `../{repo}-AB{id}`, and every step after the first runs there.

- **New Step 0 in both commands.** It does five things:
  - Fetches with `--prune`.
  - Tidies other tickets' leftover `{repo}-AB*` worktrees. A worktree is removed only if it is unlocked, clean, fully pushed and merged, or its branch was deleted on the remote. Anything else is kept and listed.
  - Creates or reuses this ticket's worktree and locks it while the session uses it.
  - Copies `.claude/settings.local.json` and any gitignored `.env.local` / `*.local.json` files into it. `settings.local.json` is added to `.git/info/exclude` if the repo doesn't ignore it.
  - Tells every subagent and Workflow agent to work only there.
- **`/implement`** creates the worktree detached at `origin/{BASE_BRANCH}` and still creates the branch in Step 4, after the plan is approved. **`/rework`** puts the worktree on the latest PR's source branch. If that branch was merged and deleted, it creates a new branch from the PR's target, as before.
- **New cleanup step.** It is Step 11 in `/implement`, F8 in the Feature workflow and Step 13 in `/rework`. It runs after the push and the Task-closing prompts. It removes the worktree and the local branch only if both are clean and fully pushed. Otherwise it keeps them and says what's uncommitted or unpushed. It never uses `--force`, and it never removes the folder the session is standing in.
- **Feature workflow.** The Feature gets one ticket worktree. The per-story wave worktrees branch from it, unchanged.
- **Opt-out.** Say "work in place" or "no worktree" to run exactly as before.
- **Frontend dependencies.** A worktree has no `node_modules`. `npm install` runs there only when the approved plan touches the frontend.

### Fixed

- `/implement` no longer cuts a ticket from, or aims its PR at, another ticket's branch when the session's folder was left on one. A current branch starting with `feature/`, `story/`, `bugfix/`, `hotfix/`, `work/`, `cherry-pick/`, `release/` or `revert/` is skipped in favour of the PR target the project's CLAUDE.md names, or the user is asked.

### Upgrade note

Projects with no `.claude/.kit-install.json` (CSIPay, for one) don't auto-update. Run `npx @chris1807/claude-kit init` there to pick this up.

Earlier versions: see the git history.
