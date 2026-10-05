# Changelog

## 2.3.5 — 2026-10-05

### Work items get an Investment Category and an Impact

User Stories, Bugs and Hot Fixes on the `Agile - CSI` process now have two restricted picklists. Serena's Monthly Executive and Backlog Grooming reports rank work by them:

- **Investment Category** (`Custom.InvestmentCategory`): Strategic Initiative, Quick Win, Risk Mitigation, Maintenance.
- **Impact** (`Custom.Impact`): Strategic, Large, Medium, Small, Tiny/One-off.

The kit now sets and maintains them like story points: Claude proposes, the user agrees.

- **`/create-work-item`** proposes both, with a one-line reason, under the draft title and in the final confirmation. It writes them on create. A Feature gets one pair that each child story inherits; the Feature itself never carries them.
- **`/quote`** and **`/quote-backlog`** propose both for items that have neither set, and write them in the same update as the points. `/quote-backlog` gets a Category · Impact column. They never overwrite a value someone already chose.
- **`/edit-work-item`** shows both, and keeps them accurate when an edit changes why an item exists or how much it matters. It proposes them when they're missing.
- **CLAUDE.md workflow** gains a "Work Item Classification" rule. It covers what each value means, that Priority is not impact, and that projects whose process lacks the fields skip them.

### `/create-work-item` and `/plan-backlog` brought up to date

Projects had been carrying fixes these two templates didn't have, so every kit update reverted those fixes. The templates now include them:

- **`/create-work-item`**:
  - Feature decomposition (Step 3F: the Decomposition Plan, order validation, and per-child mockups) happens **before** the Feature is created, so its description carries the plan.
  - The create call passes `fields` as an array of `{name, value, format}`. The old text described a JSON Patch document, which the MCP server doesn't accept.
  - Features are created in three phases: the Feature, then its children with points and `Custom.Order`, then one call to link them.
  - There is an explicit warning against `add_child`, which has no slot for AC, points or `Custom.Order`.
  - Step 9 reads the created item back to confirm it.
- **`/plan-backlog`** creates the Task and then links it with `type: "child"`. It no longer uses `add_child`, which silently dropped the hour estimate.

## 2.3.4 — 2026-10-05

### Work items serve two readers: a plain-English Summary for the PM, Technical Details for the developer

Every work item now has two parts. The **Summary** at the top is for the PM: plain English, no code. **Technical Details** below it are for the developer and Claude Code: technical, specific, and grounded in the actual codebase. This applies whether `/create-work-item` was typed or Claude ran it from a plain-language request.

- **`/create-work-item`** drafts both on every type: Feature, User Story, Bug, Hot Fix, and each child story it creates for a Feature.
  - **Summary:** 2–4 sentences on what is changing or broken, who notices, and why it matters. Things are named the way users see them, with no code identifiers, endpoints, field names, or jargon. It leads the field the form actually shows: `System.Description`, or `ReproSteps` on a Bug. On a Hot Fix it sits above Production Impact. It also appears in the final confirmation.
  - **Technical Details** replaces the old plain-language Description. It covers what changes and where, layer by layer: UI components and routes, API endpoints and validation, services and business rules, data fields and migrations, and permissions. It also lists the rules and constraints. It uses real paths and names read from the code, and marks anything unconfirmed *(unverified)*. On a Bug it names the failing code path, the error, and the *(suspected)* root cause. On a Feature it gives the architecture and the shared foundation the child stories build on. A session without the code says "Not verified against the code" instead of guessing.
  - **Fixed:** the User Story draft used to say "avoid implementation detail — that lives in tasks." But `/implement` and `/plan-backlog` create Tasks with no description, so that detail lived nowhere.
- **`/edit-work-item`** keeps both parts current when an edit changes what the item does, and proposes either one when it's missing. They show in the change-set diff like any other field.
- **`/rework`'s Task** Summary is now plain English. Code identifiers stay in its Fix section.
- **CLAUDE.md workflow:** the "Creating Work Items" rule now describes the two-reader layout.

## 2.3.3 — 2026-10-02

No changes from 2.3.2. Republished so npm's `latest` points at the current release again. A stale `v2.3.0` tag was pushed alongside `v2.3.2` and published one second later, which moved `latest` back to 2.3.0. Projects on 2.3.1 would never have auto-updated, because the update check only moves forward.

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
