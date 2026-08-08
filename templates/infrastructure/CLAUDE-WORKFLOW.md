
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
| Backlog / board audits | one agent per work item — find stale, mislabeled, orphaned, or unestimated items |
| Multi-file or cross-layer review | one agent per file/dimension, then adversarial verify before reporting |
| Repo-wide sweeps (rename, dependency bump, pattern migration) | one agent per site, worktree-isolated |

Short, single-query operations (`/status`, `/explain`, `/close-orphan-tasks`) do **not** need ultracode — they are already one pass and gain nothing from fan-out. Reach for `Workflow` when the work-list is large and the per-item work is independent.

**`/rework` always uses ultracode** — it does not wait to be asked. It fans out feedback gathering, codebase exploration, per-acceptance-criterion coverage checks, and the find → adversarially-verify review, while keeping every approval gate and write in the main loop.

**`/implement` uses ultracode scaled to the change** — its code review always fans out (find → adversarially-verify), but exploration and per-AC coverage fan out only for non-trivial / full-stack stories; a one-line config change runs lean. It's the daily driver, so it doesn't blanket-fan-out like `/rework`.

**`/plan-backlog` uses it opt-in** — only when ultracode is on.

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
| **Playwright** | Browser testing (navigate, click, fill, screenshot) |
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
4. **PR merges** into `develop` → deploys to Dev environment
5. **Create a release** using `/create-release <N>` to group work items
6. **Deploy the release** using `/deploy-release 23 staging` then `/deploy-release 23 production`
7. **Test** using Playwright MCP for browser testing
8. **Track** work items via the Azure DevOps MCP server
9. **Learn** — Claude saves what worked for next time

### Branching Strategy

#### Target Branch-to-Environment Mapping

All projects should converge to this standard. Each long-lived branch maps to an Azure subscription and environment:

| Branch | Azure Subscription | Environment | CD Pipeline Trigger |
|---|---|---|---|
| `develop` | Dev | Development | Auto on merge |
| `staging` | Staging | Staging | Auto on merge |
| `main` | Production | Production | Auto on merge (with approval gate) |

> **Note:** Some projects are not yet in sync — they may use `master` instead of `main`, or lack a `staging` branch. Until a project is migrated, the deployer and `/implement` use the **current branch** dynamically and do not assume branch names.

#### Promotion Flow

Code flows through environments via PRs — never by direct push:

```
feature/AB#1234-...  ──PR──▸  develop  ──PR──▸  staging  ──PR──▸  main
   (work branch)              (Dev)            (Staging)        (Production)
```

- **develop → staging**: PR to promote all work ready for QA/stakeholder review
- **staging → main**: PR to promote to production. May cherry-pick individual commits if only some stories are ready (see Cherry-Pick Deployments below)

#### Release Management

Releases group work items together for coordinated deployment across environments. Releases are tracked in Azure DevOps as iterations (`Release #N`) and work items are tagged with `release-{N}`.

**Creating a release:**
```
/create-release 23
```
This creates a `Release #23` iteration, assigns the selected work items to it, and tags them with `release-23`.

**Deploying a release to an environment:**
```
/deploy-release 23 staging
/deploy-release 23 production
```
This finds all work items in Release #23, cherry-picks their commits into a release branch (`release/23-to-staging`), creates a PR targeting the environment branch, and links all work items.

**Selective deployment:** Since releases are deployed via cherry-pick, you can deploy a full release or a subset. If staging has 5 user stories but only 3 should go to production, create a release with just those 3 and deploy it.

**Release flow:**
```
/create-release 23          → Groups work items into Release #23
/deploy-release 23 staging  → Cherry-picks Release #23 to staging
  (QA/testing on staging)
/deploy-release 23           → Auto-detects next env (production), deploys
```

#### Cherry-Pick Deployments

Cherry-pick specific work items to an environment without a formal release:
```
/cherry-pick AB#1234 AB#1235 production
```
This finds commits for the specified work items, cherry-picks them into a branch (`cherry-pick/<date>-to-<environment>`), and creates a PR.

#### Promoting Environments

Promote all code from one environment to the next:
```
/promote staging production
/promote                      ← auto-detects source and target from current branch
```
This creates a PR from the source branch to the target branch with a summary of all included commits.

#### Rollbacks

Roll back a deployment on any environment:
```
/rollback AB#1234 production   ← revert specific work items
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
This runs pre-flight checks, commits, pushes the current branch, and triggers the CD pipeline if on an environment branch.

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

Hot Fix work items follow the same automated checks (build, lint, tests, review) but skip manual UAT. An abbreviated confirmation is shown instead. Hot Fix PRs get a `hotfix` label. Hot Fixes target the current branch (which should be the project's production branch for production hot fixes).

#### Feature Workflow (ordered story waves)

Running `/implement` on a **Feature** implements its child User Stories in **waves** driven by the `Custom.Order` field: stories sharing the same order value are implemented **in parallel** (one agent per story, each in an isolated git worktree), and waves run sequentially in ascending order so later stories build on earlier ones. All work merges into a single `feature/AB#<id>-...` branch; quality checks, code review, UAT, and one PR happen at the feature level, and every implemented story is linked to that PR. Stories without a `Custom.Order` value run in a final catch-all wave (flagged for confirmation first).

**Work item states:** when the PR is created, each implemented child **User Story** moves to `Code Review` — the **Feature's state is never changed**. The Feature is a parent container; it advances only as its child stories are verified/closed. When the PR merges, only child **Tasks** are closed — never the stories or the Feature.

#### Slash Commands Reference

All deployment and release operations are available as slash commands:

| Command | Usage | What It Does |
|---|---|---|
| `/implement` | `/implement AB#1234` | Summarize work item → approve plan → implement → PR. On a Feature: child stories in `Custom.Order` waves, same-order stories in parallel |
| `/review` | `/review 142` | Automated code review on a PR |
| `/resolve-feedback` | `/resolve-feedback 142` | Address unresolved PR comment threads, push fixes, reply + resolve threads |
| `/deploy` | `/deploy "commit message"` | Commit, push, trigger pipeline |
| `/create-release` | `/create-release 23` | Group work items into Release #23 |
| `/deploy-release` | `/deploy-release 23 staging` | Cherry-pick release to environment |
| `/add-to-release` | `/add-to-release 24 AB#4599` | Add work items to existing release |
| `/cherry-pick` | `/cherry-pick AB#1234 AB#1235 production` | Cherry-pick specific work items |
| `/promote` | `/promote staging production` | Promote all code between environments |
| `/rollback` | `/rollback AB#1234 production` | Revert commits on an environment |
| `/status` | `/status release 24` | Check release, pipeline, or work item status |
| `/plan-backlog` | `/plan-backlog [project]` | Sweep backlog for Dev Ready stories with points and no tasks → propose child tasks with hours |
| `/cleanup-branches` | `/cleanup-branches` | Delete merged branches |
| `/close-orphan-tasks` | `/close-orphan-tasks [scope] [--dry-run]` | Close open Tasks whose parent is Ready to Deploy / Deployed / Closed |

The CD pipeline is only triggered manually when pushing directly to an environment branch. For feature/work branches, the pipeline triggers on PR merge.

### Pipeline Configuration

Each project must define its environment chain and pipeline IDs so the slash commands (`/deploy`, `/promote`, `/deploy-release`) know which pipelines to trigger and what the promotion order is.

Add this section to your project's `CLAUDE.md`:

```markdown
## Pipeline Configuration

| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| develop | Dev | My API (ID), My Client (ID) |
| staging | Staging | My API (ID), My Client (ID) |
| main | Production | My API (ID), My Client (ID) |
```

**Rules for slash commands:**
- `/deploy` triggers the pipeline(s) listed for the current branch. If the current branch is not in this table, no pipeline is triggered.
- `/promote` uses this table to determine the next environment (e.g., `develop` → `staging` → `main`).
- `/deploy-release` and `/cherry-pick` create PRs targeting environment branches listed here.
- The **order of rows** defines the promotion flow (top to bottom).

**Examples from actual projects:**

CSIPay (4 environments):
```markdown
| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| Dev | Dev | CSIPay API (12), CSIPay Client (13) |
| QA | QA | CSIPay API (12), CSIPay Client (13) |
| Staging | Staging | CSIPay API (12), CSIPay Client (13) |
| master | Production | CSIPay API (12), CSIPay Client (13) |
```

Glasswing and Monarch (1 environment currently):
```markdown
| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| develop | Dev | CD - Development (28) |
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
```
