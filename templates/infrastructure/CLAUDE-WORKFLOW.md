
## Claude Kit Workflow

This project uses [Claude Kit](https://github.com/Christopher-Waters/claude-kit) — a standardized set of agents, hooks, MCP servers, and workflows installed via `npx @chris1807/claude-kit init`.

> **This workflow is built for Azure DevOps.** Work items, branches, pull requests, releases (as iterations), and CD pipelines all live in Azure DevOps. The slash commands below talk to it through the Azure DevOps MCP server — `AB#1234` ids refer to Azure DevOps work items, PR numbers refer to Azure Repos pull requests, and pipeline ids refer to Azure Pipelines build definitions. If your project lives somewhere else (GitHub, GitLab, Jira), these commands will not work as-is.

### Agent Pipeline

When given a task, Claude Code can delegate through specialized agents:

```
You (give task)
  ├── Explore → finds relevant files (built-in)
  ├── Plan → designs the approach (built-in)
  ├── mockup → creates HTML screen mockups before implementation
  ├── backend / frontend / legacy → implements code
  ├── deployer → commits, pushes, triggers CD pipeline
  ├── db-admin → queries/fixes MongoDB data
  ├── test-runner → runs xUnit, Vitest, Playwright tests
  ├── qa → drives a real browser on a deployed environment, regression-tests the affected screens
  ├── build-validator → confirms builds pass
  ├── lint-checker → runs ESLint and dotnet format
  ├── security-auditor → scans for secrets, vulnerabilities
  ├── azure-ops → manages Azure infrastructure
  └── reviewer → reviews code quality
```

Orchestration, Azure DevOps work-item management, UAT checklist generation, and ad-hoc API testing are handled directly by the main Claude Code loop (via the `Workflow` tool, the Azure DevOps MCP server, the `/implement`/`/rework` UAT steps, and curl) — they no longer have dedicated agents.

### Ultracode (multi-agent workflows)

The **agent pipeline** above is sequential delegation: one specialist agent at a time, through the `Task` tool. **Ultracode** is a different, harness-level gear — it authorizes the `Workflow` tool to fan out many agents in parallel under a deterministic script. The two compose; ultracode does not replace the pipeline, it parallelizes the parts of it that are embarrassingly parallel.

Ultracode is **opt-in**. It is on only when a system-reminder confirms it, when you type `ultracode` in a prompt, or when a slash command's instructions say to use `Workflow`. When it is off, everything below runs the normal sequential way — nothing changes.

**Who can call `Workflow`:** the main Claude Code loop, and slash commands (they expand into the main conversation). **Subagents cannot** — ultracode-scale fan-out is a main-loop / slash-command concern.

**Kit operations that benefit from ultracode (when it's on):**

| Operation | Fan-out unit |
|-----------|--------------|
| `/plan-backlog` | one agent per Dev Ready story — analyze, point, and propose tasks in parallel |
| `/plan-sprint` | one agent per sprint item — analyze and propose tasks in parallel |
| `/quote-backlog` | one agent per swept item (stories in Design Approved, bugs in New) — completeness review, duplicate check, estimate in parallel |
| Backlog / board audits | one agent per work item — find stale, mislabeled, orphaned, or unestimated items |
| Multi-file or cross-layer review | one agent per file/dimension, then adversarial verify before reporting |
| Repo-wide sweeps (rename, dependency bump, pattern migration) | one agent per site, worktree-isolated |

Short, single-query operations (`/track`, `/explain`, `/close-orphan-tasks`) do **not** need ultracode — they are already one pass and gain nothing from fan-out. Reach for `Workflow` when the work-list is large and the per-item work is independent.

**`/rework` always uses ultracode** — it does not wait to be asked. It fans out feedback gathering, codebase exploration, per-acceptance-criterion coverage checks, and the find → adversarially-verify review, while keeping every approval gate and write in the main loop.

**`/implement` uses ultracode scaled to the change** — its code review always fans out (find → adversarially-verify), but exploration and per-AC coverage fan out only for non-trivial / full-stack stories; a one-line config change runs lean. It's the daily driver, so it doesn't blanket-fan-out like `/rework`.

**`/plan-backlog`, `/plan-sprint`, and `/quote-backlog` use it opt-in** — only when ultracode is on.

### Sensitive Data Policy

**NEVER query, display, or expose sensitive PII fields from the database — even if the values are encrypted.** This includes TIN, SSN, EIN, TaxId, BankAccountNumber, RoutingNumber, and any `Encrypted*` variants. Even encrypted/hashed values must not appear in output, logs, or summaries. When querying collections that may contain sensitive fields, always use explicit inclusion projections listing only the non-sensitive fields needed. If a user requests access to sensitive data, direct them to use the application UI.

### Automated Hooks

These run automatically — no action needed:

| When | What Happens |
|------|-------------|
| **Before any Bash command** | Sensitive data blocker prevents database queries that reference TIN, SSN, or other PII fields |
| **Before any MCP database tool** | Sensitive data MCP blocker prevents MCP database queries that reference PII fields |
| **After any Bash/MCP/Read/Grep command** | Sensitive data output blocker scans results for PII field names and blocks exposure |
| **Before any file write** | Secret blocker scans for hardcoded credentials and blocks them |
| **Before any file edit** | Protected files guard warns/blocks edits to production configs |
| **After any file edit** | Auto-formatter runs (dotnet format for .cs, eslint --fix for .ts) |
| **After any file edit** | Test suggestions appear for related test files |
| **When Claude stops** | UAT reminder if a feature was implemented |
| **When Claude stops** | Self-improvement prompt to save learnings to memory |

### MCP Servers Available

| Server | What It Does |
|--------|-------------|
| **Azure DevOps** *(core — drives every slash command)* | Work items, repos, pull requests, pipelines, wiki, test plans, advanced security |
| **Playwright** | Browser testing (navigate, click, fill, screenshot) — **required by `/qa`** |
| **MongoDB** | Direct database queries and updates |
| **Microsoft Teams** | Send/read team messages and notifications |
| **Stripe** | Payment management (when configured) |
| **Azure** | 40+ Azure services via CLI |

### Memory System

Claude maintains persistent memory across sessions in `~/.claude/projects/.../memory/`. This includes:
- **User preferences** — how you like to work
- **Feedback patterns** — what to do and what to avoid (self-improving)
- **Project context** — decisions, priorities, blockers
- **References** — URLs, test accounts, external resources

### Development Workflow

1. **Pick a work item** from Azure DevOps (or describe what you need)
2. **Claude implements** using `/implement AB#<id>` (auto-creates branch)
3. **Hooks guard** against secrets and bad patterns automatically
4. **PR merges** into `main` — the compare branch. **Nothing deploys yet.** The work item stays in `Code Review` until it is promoted
5. **Promote or release** — `/promote main dev` carries everything on `main` to Dev; `/create-release <N>` groups work items so `/deploy-release <N> test` → `staging` → `prod` can carry just those
6. **Say who verifies** — before the merge, the command asks who each product group (`COM`, `PAY`, …) should be assigned to in the target environment, offering the non-developer names already on those work items
7. **The promotion PR merges** — for `dev`, `test`, and `staging`, the deploy commands wait for Serena to approve and then complete the PR themselves; a `prod` PR is always merged by a person. That merge triggers the environment's CD pipeline. The command watches it and, once it's green, sets the work items to `Testing`, `Staging`, or `Deployed` **and** assigns them to the approved verifiers — automatically, no reply needed
8. **Test** using Playwright MCP for browser testing
9. **Track** work items via the Azure DevOps MCP server
10. **Learn** — Claude saves what worked for next time

### Story Points & Dev Ready Policy

These rules apply to **every** command or flow that creates or estimates work items:

1. **Every work item Claude creates gets a proposed story point estimate** — User Stories and Bugs are never created unpointed by default. Estimates use the modified Fibonacci scale (`1, 2, 3, 5, 8, 13, 21`), calibrated for a **senior developer working with Claude assistance** — no ramp-up padding; pad only for what seniority + Claude can't shortcut (novel work, missing AC, cross-team coordination, external dependencies).
2. **The user must agree before points are written.** Claude proposes the number with a one-line rationale; the user confirms, adjusts (their number wins), or skips. Points are never set silently.
3. **Task hours come from complexity, not from the top of the points band.** Story points give a Task an hour *band* (low / medium / high). Which end of that band the estimate lands on is decided by the complexity of the work, judged separately from its size: low complexity → the low end, medium → the middle, high → the high end. Points already carry size, so a big-but-routine story is a high-points, low-complexity Task and gets low-end hours. The bands are contiguous and anchored to a **6-hour day** (1 pt = under 2 hrs, 2 pts = up to half a day, 3 pts = half a day to 2 days, 5 pts = 2–4 days, 8 pts = about a week, and up) — a 1-pointer can never cost more than a 2-pointer's floor. Every hour proposal states the band and the complexity call that picked within it. See `/plan-backlog` Step 5b for the table and the complexity rubric.
4. **Setting points moves the item to Dev Ready.** Any time story points are written to a **User Story**, **Bug**, or **Hot Fix**, `System.State` is set to `Dev Ready` in the same update. Never for Features or Tasks (a Feature's state is never touched; Tasks carry hour estimates, not points), and never backward — an item already past Dev Ready keeps its state, with a note.
5. **An item that can't be quoted drops out of the estimating queue — by a mechanism that depends on its type.** When `/quote` or `/quote-backlog` can't produce a number because information is missing — no acceptance criteria (or, on a bug, no repro steps), contradictory description, unbounded scope, or a possible duplicate the creator has to confirm — the item drops out of the sweep along with the feedback comment, so the next run isn't re-analyzing items still waiting on their creator:
   - **User Story** → moves from `Design Approved` back to `Design Review`. Only from `Design Approved`; an item at `Dev Ready` or anything `Active` or later keeps its state.
   - **Bug / Hot Fix** → gets a **`needs-info` tag**, state left at `New`. **These types have no design states** in the CSI Development template — no `Design Review` and no `Design Approved` — so there is no earlier state to send them back to. Append to `System.Tags`; never overwrite the field. Removing the tag re-queues the bug.
   - **Feature / Task** → neither; report the gap and stop.

   An item that merely **needs to be split** keeps its state and gets no tag — the work is understood, nothing is missing.

   **The drop-out mechanism has no expiry, so every sweep must audit it.** Removing the `needs-info` tag is the *only* thing that re-queues a bug, and moving a story back to `Design Approved` is the only thing that re-queues a story. A creator who supplies the missing information but leaves the tag on — or answers in a comment instead of editing the field — makes the item invisible to every future sweep, permanently. That failure looks exactly like a clean backlog. `/quote-backlog` Step 2b therefore audits tagged items for activity after the tag was applied and reports the stale ones; it never clears a tag on the creator's behalf. Two traps when writing such a check: automation bots bump a revision after nearly every human write, so the *latest* revision author is unreliable — scan the whole range after the tag revision; and a `System.CommentCount` increase counts as a creator response.
6. **Never assume two work item types share a state list.** WIQL doesn't validate state names, so a query filtering on a state the type doesn't have returns **zero rows instead of an error** — the classic symptom is a backlog sweep that silently never surfaces a single bug. Confirm with `mcp__azure-devops__wit_work_item` (`action: get_type`) before writing a state name into a query or an update. In CSI Development (verified 2026-09-06): `User Story` has `New → Dev Ready → In Design → Design Review → Design Approved → Active → Code Review → Ready for Testing → Testing → Ready for Staging → Staging → Ready to Deploy → Deployed → Closed`; `Bug` and `Hot Fix` have the same list minus the three design states (`New → Dev Ready → Active → Code Review → …`). `Ready for Staging` and `Staging` were added on 2026-09-06 so every environment has a state — see **Work Item States ↔ Environments** below.

### Branching Strategy

#### Target Branch-to-Environment Mapping

All projects converge to this standard. `main` is the **compare branch** — the default branch, the one feature PRs target, and the one every environment branch is compared against. **Merging into `main` deploys nothing.** Each environment has its own long-lived branch, and a PR merging into that branch is what triggers its CD pipeline:

| Branch | Environment | CD Pipeline Trigger |
|---|---|---|
| `main` | — (compare / integration branch) | **None** — merging a PR into `main` does not deploy |
| `dev` | Development | Auto when a PR merges into `dev` |
| `test` | Test (QA) | Auto when a PR merges into `test` |
| `staging` | Staging | Auto when a PR merges into `staging` |
| `prod` | Production | Auto when a PR merges into `prod` |

Branch names are lowercase. COMPASS and CSIPay are on this layout (CSIPay renamed its branches on 2026-09-04; `test` replaced `QA`).

> **Note:** A project that hasn't migrated yet (e.g. one that still has only `main` and `develop`) keeps working — the deployer and every slash command read the project's **Pipeline Configuration** table and use the **current branch** dynamically; no branch names are hardcoded.

#### Promotion Flow

Code flows through environments via PRs — never by direct push. Every arrow below is a PR, and every merge **after** `main` deploys:

```
feature/AB#1234-...  ──PR──▸  main  ──PR──▸  dev  ──PR──▸  test  ──PR──▸  staging  ──PR──▸  prod
   (work branch)            (compare,      (Dev)         (Test)         (Staging)        (Production)
                            no deploy)
```

- **feature → main**: the `/implement` PR. Code review happens here. Merging it deploys nothing.
- **main → dev**: `/promote main dev` — usually everything on `main`, so developers can smoke-test on Dev.
- **dev → test**: `/promote dev test` or `/deploy-release <N> test` — hands the work to QA.
- **test → staging**: `/deploy-release <N> staging` — only what QA passed (`Ready for Staging`).
- **staging → prod**: `/deploy-release <N> prod` — only what stakeholders approved (`Ready to Deploy`). Cherry-pick a subset when only some stories are ready (see Cherry-Pick Deployments below).

#### Work Item States ↔ Environments

Every environment in the chain has a work item state, so the board shows where each story physically is. The **"Ready for …" states are human gates** — QA or stakeholders set them when something passes; the slash commands never do. The **environment states** (`Testing`, `Staging`, `Deployed`) are set by the promotion commands once the PR into that branch has merged and its CD pipeline has come back green.

| Branch | Environment | Gate — items should already be in… | Set once the PR into this branch merges |
|---|---|---|---|
| `main` | — | `Code Review` (the `/implement` PR is open) | *(no change — nothing deployed)* |
| `dev` | Dev | `Code Review` (merged to `main`) | `Ready for Testing` |
| `test` | Test | `Ready for Testing` | `Testing` |
| `staging` | Staging | `Ready for Staging` | `Staging` |
| `prod` | Production | `Ready to Deploy` | `Deployed` |

`/qa` is the exception that proves the rule: it tests a work item in a browser and posts a pass/fail comment, but it **never writes a state** — not even `Ready for Testing`.

Human-only transitions — no slash command ever makes these: `Testing → Ready for Staging` (QA sign-off), `Staging → Ready to Deploy` (stakeholder / UAT sign-off), `Deployed → Closed` (verified in production).

How the commands use this table:

- **Gate check before the PR.** `/deploy-release`, `/cherry-pick`, and `/promote` compare each carried work item's state against the gate for the target environment. Anything behind the gate (e.g. still `Testing` when deploying to `staging`) is flagged and the user decides whether to include it. Items *ahead* of the gate (e.g. already `Deployed` on a cherry-pick to `prod`) are reported and left alone.
- **Advance on a green pipeline, automatically.** `/promote`, `/cherry-pick`, and `/deploy-release` do not stop at the PR. They poll it until it is `completed`, then poll the target branch's CD pipeline until every run finishes. Only on `succeeded` do they write the new state — for every carried User Story, Bug, and Hot Fix, never a Feature or Task, and never backward. A failed or canceled run changes **nothing** and is reported with the log link. `/track` reports items whose state lags the branch their commits are on and offers to catch them up.
- **Auto-merge below production.** When the target is `dev`, `test`, or `staging`, all three commands poll the PR until **Serena** (the AI reviewer) votes, then complete it with autocomplete — remaining branch policies still gate the merge, work item transitions are left off so the command's own state logic owns them, and a branch policy that isn't passing is a stop, never a bypass. A rejection or *waiting for author* vote stops the merge and reports her threads. A PR into `prod` (or into `main`) is **always** merged by a person.
- **Assign the verifier at the same time.** The state change hands the item to a person, so the same three commands ask **before the merge** who each group of items should go to, then apply the assignee alongside the state once the pipeline is green. See **Verifier Assignment** below.
- **Never assume the state list.** Confirm with `mcp__azure-devops__wit_work_item` (`action: get_type`) on an unfamiliar project before writing a state name — a bad name is accepted silently by a query and rejected only at write time.

#### Verifier Assignment

Moving an item to `Testing`, `Staging`, or `Deployed` puts it on someone's plate, so `/promote`, `/cherry-pick`, and `/deploy-release` also change who owns it. The developer implemented it; from here on it belongs to whoever checks it in that environment.

- **Grouped by product prefix.** Work item titles are `PREFIX - Title`, so the commands group the carried items by prefix (`COM`, `PAY`, `CDA`, …) and ask **one question per group**. A staging → prod deploy carrying 2 `COM` and 2 `PAY` items asks twice; answering with the same person both times is fine, and `all 1` gives the whole batch to one person.
- **Candidates come from the work items, never from a directory.** For each group the commands read the items' own history — who set the gate state (`Ready for Staging` / `Ready to Deploy`, from `list_revisions`), who created the item, who commented on it, who last edited it — then subtract the developers (current assignee, PR author, commit authors). What's left are the non-developer names actually attached to that work, ranked with the sign-off setter first. No name is ever invented.
- **Asked before the merge, applied after.** The question comes while the PR is still in review and requires an explicit `yes`; nothing is written until the CD pipeline reports success. Then state and `System.AssignedTo` are set in the same update, and the report shows `was → now` for both so a wrong assignment is one edit to undo.
- **`Leave the current assignee alone`** is always an option — the commands never clear an assignee, and never touch a Feature's or a Task's assignee.

#### Release Management

Releases group work items together for coordinated deployment across environments. Releases are tracked in Azure DevOps as iterations (`Release #N`) and work items are tagged with `release-{N}`.

**Creating a release:**
```
/create-release 23
```
This creates a `Release #23` iteration, assigns the selected work items to it, and tags them with `release-23`.

**Deploying a release to an environment:**
```
/deploy-release 23 test
/deploy-release 23 staging
/deploy-release 23 prod
```
This finds all work items in Release #23, checks each one against the target environment's gate state, cherry-picks their commits into a release branch (`release/23-to-staging`), creates a PR targeting the environment branch, links all work items, asks who verifies each product group, merges the PR once Serena approves it (`dev`/`test`/`staging` only — a `prod` PR waits for a person), and — once the merge's CD pipeline comes back green — advances them to the environment's state (`Testing`, `Staging`, `Deployed`) and assigns them to those verifiers.

**Selective deployment:** Since releases are deployed via cherry-pick, you can deploy a full release or a subset. If staging has 5 user stories but only 3 are `Ready to Deploy`, create a release with just those 3 and deploy it.

**Release flow:**
```
/create-release 23          → Groups work items into Release #23
/deploy-release 23 test     → Cherry-picks Release #23 to test → items go to Testing
  (QA passes → sets Ready for Staging)
/deploy-release 23          → Auto-detects next env (staging) → items go to Staging
  (stakeholders approve → set Ready to Deploy)
/deploy-release 23          → Auto-detects next env (prod) → items go to Deployed
```

#### Cherry-Pick Deployments

Cherry-pick specific work items to an environment without a formal release:
```
/cherry-pick AB#1234 AB#1235 prod
```
This finds commits for the specified work items, checks them against the target's gate state, cherry-picks them into a branch (`cherry-pick/<date>-to-<environment>`), creates a PR, asks who verifies each product group, merges the PR once Serena approves it (`dev`/`test`/`staging` only — a `prod` PR waits for a person), and — once the merge's CD pipeline is green — advances and assigns the work items.

#### Promoting Environments

Promote all code from one environment to the next:
```
/promote main dev
/promote staging prod
/promote                      ← auto-detects source and target from current branch
```
This creates a PR from the source branch to the target branch with a summary of all included commits and their work items, checks the work items against the target's gate state, asks who verifies each product group, merges the PR once Serena approves it (`dev`/`test`/`staging` only — a `prod` PR waits for a person), and — once the merge's CD pipeline is green — advances and assigns them. `main → dev` is the usual first hop after feature PRs merge.

#### Rollbacks

Roll back a deployment on any environment:
```
/rollback AB#1234 prod         ← revert specific work items
/rollback last staging         ← revert the most recent deployment
```
This creates a revert branch, reverts the specified commits, runs pre-flight checks, and creates a PR.

For emergency production rollbacks, the `/rollback` command already runs pre-flight checks and skips UAT. Treat the resulting PR as urgent and flag the user accordingly.

#### Deploying Changes

Commit, push, and deploy the current changes:
```
/deploy "Add payment export feature"
/deploy                       ← auto-generates commit message
```
This runs pre-flight checks, commits, pushes the current branch, and triggers the CD pipeline if on an environment branch (`dev`, `test`, `staging`, `prod`). On `main` or a work branch nothing is triggered — `main` has no pipeline.

#### Branch Naming Convention

When `/implement AB#<id>` is run, a branch is created off the current branch based on the Azure DevOps work item type:

| Work Item Type | Branch Prefix | Example |
|---|---|---|
| Feature | `feature/` | `feature/AB#1234-add-payment-export` |
| User Story | `story/` | `story/AB#1235-user-can-view-history` |
| Bug | `bugfix/` | `bugfix/AB#1236-fix-login-redirect` |
| Hot Fix | `hotfix/` | `hotfix/AB#1237-fix-crash-on-submit` |
| (other) | `work/` | `work/AB#1238-update-dependencies` |

Format: `{prefix}AB#{id}-{sanitized-title}` (title lowercased, special chars replaced with hyphens, max 50 chars)

> **Note:** The Azure DevOps work item type is "Hot Fix" (two words), but the branch prefix and PR label use `hotfix` (one word, lowercase).

#### PR Targeting

PRs always target the branch you were on when `/implement` was invoked. The base branch is captured dynamically at the start — no assumptions about branch names.

#### Hot Fix Workflow

Hot Fix work items follow the same automated checks (build, lint, tests, review) but skip manual UAT. An abbreviated confirmation is shown instead. Hot Fix PRs get a `hotfix` label. Hot Fixes target the current branch — for a production hot fix, start on `prod` so the PR merges (and deploys) straight there. **Then bring the fix back to `main`:** open a second PR from the same hotfix branch into `main` (or `/cherry-pick AB#<id> main`) so the next `main → dev` promotion doesn't overwrite it. A hot fix that lives only on `prod` is lost on the next release.

#### Feature Workflow (ordered story waves)

Running `/implement` on a **Feature** implements its child User Stories in **waves** driven by the `Custom.Order` field: stories sharing the same order value are implemented **in parallel** (one agent per story, each in an isolated git worktree), and waves run sequentially in ascending order so later stories build on earlier ones. All work merges into a single `feature/AB#<id>-...` branch; quality checks, code review, UAT, and one PR happen at the feature level, and every implemented story is linked to that PR. Stories without a `Custom.Order` value run in a final catch-all wave (flagged for confirmation first).

**Work item states:** `/implement` moves the work item to `Active` when implementation starts — for a single work item (User Story, Bug, Hot Fix) right after the branch is created; for a Feature, each child story goes `Active` as its wave begins. When the PR is created, each implemented child **User Story** moves to `Code Review` — the **Feature's state is never changed**. The Feature is a parent container; it advances only as its child stories are verified/closed. Only child **Tasks** are ever closed — never the stories or the Feature. From `Code Review` onward the stories follow the **Work Item States ↔ Environments** table above as they are promoted.

**Hours live on the Task.** `/implement` will not implement a story that has no open child Task: if there isn't one, it proposes a title and an hour estimate (from the story's points, same mapping `/plan-backlog` uses — points set the hour band, complexity picks where in the band it lands) and creates it once the user agrees — exactly one per story, inheriting the parent's assignee, area, and iteration. When the PR is created, that Task is closed with the hours worked logged to `CompletedWork` and `RemainingWork` zeroed. Closing happens at **PR creation**, not at merge, so hours are recorded while they're still known. Never enable Azure DevOps's "Complete associated work items" when merging — it transitions the parent too.

#### Slash Commands Reference

All deployment and release operations are available as slash commands:

| Command | Usage | What It Does |
|---|---|---|
| `/implement` | `/implement AB#1234` | Summarize work item → approve plan → ensure an open child Task with hours → implement → PR (closes the Task, logs hours). On a Feature: child stories in `Custom.Order` waves, same-order stories in parallel |
| `/review` | `/review 142` | Automated code review on a PR |
| `/resolve-feedback` | `/resolve-feedback 142` | Address unresolved PR comment threads, push fixes, reply + resolve threads |
| `/deploy` | `/deploy "commit message"` | Commit, push, trigger pipeline (only on `dev`/`test`/`staging`/`prod` — never on `main`) |
| `/create-release` | `/create-release 23` | Group work items into Release #23 |
| `/deploy-release` | `/deploy-release 23 staging` | Gate-check → cherry-pick release to environment → PR → ask who verifies → merge on Serena's approval (below prod) → advance + assign on a green pipeline |
| `/add-to-release` | `/add-to-release 24 AB#4599` | Add work items to existing release |
| `/cherry-pick` | `/cherry-pick AB#1234 AB#1235 prod` | Gate-check → cherry-pick specific work items → PR → ask who verifies → merge on Serena's approval (below prod) → advance + assign on a green pipeline |
| `/promote` | `/promote main dev` | Promote all code between environments (`main → dev → test → staging → prod`) → ask who verifies → merge on Serena's approval (below prod) → advance + assign on a green pipeline |
| `/rollback` | `/rollback AB#1234 prod` | Revert commits on an environment |
| `/track` | `/track release 24` | Check release, pipeline, environment, or work item status; flags work items whose state lags their environment |
| `/where` | `/where AB#1234` | Show which environment branches contain a work item's commits |
| `/qa` | `/qa AB#1234 [env]` | Verify the item is fully deployed with a green pipeline → open the app in a real browser → sign in as a test account → full regression of the screens the story touched → pass/fail comment (never a state change) |
| `/plan-backlog` | `/plan-backlog [project]` | Sweep backlog for Dev Ready stories with points and no tasks → propose child tasks with hours |
| `/plan-sprint` | `/plan-sprint [project]` | Sweep the current sprint for stories/bugs with no child tasks → propose one child task with hours per item |
| `/quote-backlog` | `/quote-backlog [project]` | Sweep backlog for unpointed items ready to estimate — stories in `Design Approved`, **bugs in `New`** (bugs have no design states) → review completeness, check for duplicates, suggest rewrites, propose points + creator comments (10 at a time, approval-gated). Pointed items move to Dev Ready; stories that can't be quoted move back to **Design Review**, bugs that can't be quoted get a **`needs-info`** tag, so the next sweep skips them. Every run also audits the drop-out queue (tagged bugs **and** stories bounced to Design Review) and reports any whose creator answered but which nobody returned to the sweep — neither mechanism expires, so those are otherwise invisible forever |
| `/quote` | `/quote AB#1234` | Estimate story points for one work item; on approval, sets the points and moves the item to Dev Ready. If it can't be estimated, offers to send a story back to **Design Review** or tag a bug **`needs-info`** |
| `/create-work-item` | `/create-work-item [description]` | Interactively draft and create a Feature, Bug, User Story, or Hot Fix — proposes story points (user must agree) and creates pointed items in Dev Ready; on a Feature, also drafts its child stories with `Custom.Order` waves |
| `/edit-work-item` | `/edit-work-item AB#1234 [what to change]` | Revise an existing work item field-by-field. On a Feature, cascades the change into its child stories — updates, adds, retires, and re-sequences `Custom.Order` waves — with a safety gate on anything already past Dev Ready |
| `/cleanup-branches` | `/cleanup-branches` | Delete merged branches |
| `/close-orphan-tasks` | `/close-orphan-tasks [scope] [--dry-run]` | Close open Tasks whose parent is Ready to Deploy / Deployed / Closed |

The CD pipeline is only triggered manually when pushing directly to an environment branch (`dev`, `test`, `staging`, `prod`). For feature/work branches and for `main`, nothing is triggered — a feature PR merging into `main` deploys nothing; the first deployment happens when `main` is promoted to `dev`.

### Pipeline Configuration

Each project must define its compare branch, its environment chain, and its pipeline IDs so the slash commands (`/deploy`, `/promote`, `/deploy-release`, `/cherry-pick`, `/where`, `/track`) know which pipelines to trigger and what the promotion order is.

Add this section to your project's `CLAUDE.md`:

```markdown
## Pipeline Configuration

| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| main | — (compare branch, no deployment) | — |
| dev | Dev | My API (ID), My Client (ID) |
| test | Test | My API (ID), My Client (ID) |
| staging | Staging | My API (ID), My Client (ID) |
| prod | Production | My API (ID), My Client (ID) |
```

**Rules for slash commands:**
- The **first row is the compare branch**. Feature PRs target it. It has no pipeline — merging into it deploys nothing. A row whose Pipeline(s) cell is `—` is never triggered.
- The **order of rows** defines the promotion flow (top to bottom): `main → dev → test → staging → prod`.
- `/deploy` triggers the pipeline(s) listed for the current branch. If the current branch is not in this table, or its pipeline cell is `—`, no pipeline is triggered.
- `/promote` uses this table to determine the next environment (the next row down).
- `/deploy-release` and `/cherry-pick` create PRs targeting environment branches listed here, and use the **Work Item States ↔ Environments** table to gate-check and advance work items.
- `/where` and `/track` check every row; the compare branch reports as "merged to main", not as a deployment.

**Examples from actual projects:**

COMPASS:
```markdown
| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| main | — (compare branch, no deployment) | — |
| dev | Dev | Compass API (YAML) (32), Compass Client (YAML) (33) |
| test | Test | Compass API (YAML) (32), Compass Client (YAML) (33) |
| staging | Staging | Compass API (YAML) (32), Compass Client (YAML) (33) |
| prod | Production | Compass API (YAML) (32), Compass Client (YAML) (33) |
```

CSIPay:
```markdown
| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| main | — (compare branch, no deployment) | — |
| dev | Dev | CSIPay API (12), CSIPay Client (13) |
| test | Test | CSIPay API (12), CSIPay Client (13) |
| staging | Staging | CSIPay API (12), CSIPay Client (13) |
| prod | Production | CSIPay API (12), CSIPay Client (13) |
```

Glasswing and Monarch (not yet migrated — 1 environment):
```markdown
| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| main | — (compare branch, no deployment) | — |
| develop | Dev | CD - Development (28) |
```

### Environment URLs

`/qa` opens the app in a real browser, so it needs to know where each environment is hosted and which test account to sign in as. Without this section `/qa` reports and stops rather than guessing a hostname.

Add this to your project's `CLAUDE.md` — **above the `## Claude Kit Workflow` heading.** Everything from that heading to the end of the file is replaced on each kit update, so configuration placed below it is lost.

```markdown
## Environment URLs

| Branch | Environment | App URL | API URL |
|--------|------------|---------|---------|
| (none) | local | http://localhost:5173 | https://localhost:7001 |
| dev | Dev | https://dev.myapp.example.com | https://dev.api.myapp.example.com |
| test | Test | https://test.myapp.example.com | https://test.api.myapp.example.com |
| staging | Staging | https://staging.myapp.example.com | https://staging.api.myapp.example.com |

**Sign-in:** form at `/login` — app-issued JWT, no SSO. Signed-in landing: `/dashboard`.

**Test accounts** — values live in environment variables; never write a password here.

| Role | Username variable | Password variable | Default |
|------|-------------------|-------------------|---------|
| Admin | `MYAPP_QA_ADMIN_USERNAME` | `MYAPP_QA_ADMIN_PASSWORD` | yes |
| Provider | `MYAPP_QA_PROVIDER_USERNAME` | `MYAPP_QA_PROVIDER_PASSWORD` | |
```

**Rules for slash commands:**
- **Branch names must match the `## Pipeline Configuration` table** row for row. The two tables are joined on the branch column — `/qa` reads the URL here and the pipeline ID there. A mismatch is a configuration error worth reporting.
- **There is no `prod` row, deliberately.** `/qa` refuses production: an unattended regression pass signs in and clicks through live member data.
- **Include the rows below the one you test.** The row immediately below the target serves the pre-change build, which is how `/qa` tells a regression this story caused from a bug that was already there.
- **App URL is required; API URL is optional** — it is used to attribute a failing network call to the backend rather than the screen.
- **`Sign-in:`** is optional prose. Include it when the login route is not `/login`, when the landing page is not obvious, or — importantly — when sign-in goes through **SSO / Entra ID with MFA**. Say so, and `/qa` reports that it cannot sign in unattended instead of hanging on a browser prompt.
- **Test accounts** are required by `/qa` and nothing else. The `Default` column marks the account used when `--role` is not given; if no row is marked, the first row wins. A second role lets `/qa` verify that restricted controls are correctly *absent* — a class of bug a manual checklist rarely catches.
- **Never put a credential in this table.** Only variable names. The values belong in your shell profile — see Environment Setup below.

**Example from an actual project:**

COMPASS:
```markdown
| Branch | Environment | App URL | API URL |
|--------|------------|---------|---------|
| (none) | local | http://localhost:5173 | https://localhost:7169 |
| dev | Dev | https://dev.compass.caresolutions.com | https://dev.api.compass.caresolutions.com |
| test | Test | https://test.compass.caresolutions.com | https://test.api.compass.caresolutions.com |
| staging | Staging | https://staging.compass.caresolutions.com | https://staging.api.compass.caresolutions.com |
```

### Environment Setup

Each team member needs to set their own environment variables (never commit these):

```bash
# MongoDB (required for db-admin agent)
export MONGODB_CONNECTION_STRING="mongodb+srv://..."

# Stripe (required when payment integration is active)
export STRIPE_SECRET_KEY="sk_test_..."

# Azure (use az login instead of env vars)
az login

# Microsoft Teams MCP — no env vars needed. First invocation prints a
# device code + URL to sign in via Microsoft Graph (OAuth device flow).

# QA test accounts (required for /qa — browser testing on a deployed environment).
# One pair per role. The variable NAMES are declared in the project's
# `## Environment URLs` section; the VALUES live only here, never in any file.
# Use throwaway QA accounts with least privilege, never a personal login.
export COMPASS_QA_ADMIN_USERNAME="qa-admin@example.com"
export COMPASS_QA_ADMIN_PASSWORD="..."
export COMPASS_QA_PROVIDER_USERNAME="qa-provider@example.com"
export COMPASS_QA_PROVIDER_PASSWORD="..."
```

`/qa` reads these itself **inside a subagent** and fills the login form directly. It never prints a value, never writes one to a file, and never includes one in a report or a work item comment. If your app's sign-in requires MFA or SSO, unattended login is not possible — say so in the `Sign-in:` line of `## Environment URLs` and `/qa` will report that instead of hanging on a browser prompt.
