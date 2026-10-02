# Changelog

## 2.3.2 — 2026-10-02

### Work items are always created through `/create-work-item`

Asking Claude in plain words to "log a bug", "make a story", or "open a ticket" now runs `/create-work-item`, the same as typing the command. That means the prior-art and duplicate checks, the title prefix, the AC field, proposed points, and the user's approval of the draft all apply. Claude no longer creates the item with a direct `wit_work_item_write` call.

- **New `UserPromptSubmit` hook, `work-item-intent.sh`.** When a prompt reads like a creation request, it adds a note telling Claude to run `/create-work-item` through the Skill tool. It never blocks. It skips prompts that start with `/`, and it ignores "feature flag" and "feature branch". The note is conditional, so a false positive is simply ignored.
- **`/create-work-item`'s description** now says to use it for any work-item creation request, so Claude picks it up even without the hook. If the request already names the type ("log a **bug**…"), Step 1 doesn't ask for it again. The type is shown in the Step 2 confirmation instead.
- **CLAUDE.md workflow** gains a "Creating Work Items" rule. It covers items Claude decides to raise itself. It also carves out work items a command creates as one of its own steps, such as child Tasks from `/implement`, `/rework`, and `/plan-backlog`, and child stories from `/create-work-item` and `/edit-work-item`.

Existing installs get the hook through the normal settings merge. User-added hooks are kept.

## 2.3.1 — 2026-09-29

The first published release of this work. 2.3.0 was tagged locally but never published.

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

- `/rework` no longer pushes to a branch that no PR is watching. The latest PR's status now decides the branch: an `active` or `abandoned` PR's branch is built on. A `completed` PR, or one whose branch was deleted, gets a new branch from its target. That applies even when the merged branch still exists, so a squash-merged PR's changes don't show up again. The new branch gets a `-rework-{N}` suffix if the merged branch kept its name. Whenever the push lands on a branch without an active PR, Step 12 opens a new PR into the old PR's target and links it to the work item. Step 3's summary says up front when that will happen.

### Upgrade note

Projects with no `.claude/.kit-install.json` (CSIPay, for one) don't auto-update. Run `npx @chris1807/claude-kit init` there to pick this up.

Earlier versions: see the git history.
