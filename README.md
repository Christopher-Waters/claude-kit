# Claude Kit

> A [Claude Code](https://claude.ai/code) starter kit **built for Azure DevOps teams** — agents, hooks, MCP servers, and slash commands that automate the full work item → branch → PR → release → deploy lifecycle. Installed into any project with a single `npx` command.

[![npm](https://img.shields.io/npm/v/@chris1807/claude-kit)](https://www.npmjs.com/package/@chris1807/claude-kit)

---

## About

Claude Kit installs a complete AI development infrastructure into any project that uses **Azure DevOps** for work tracking, source control (Azure Repos), and CI/CD (Azure Pipelines). It includes specialized agents that handle specific tasks (deployment, database ops, code review), security hooks that prevent mistakes automatically, MCP server connections to your tools (Azure DevOps, databases, Teams, Stripe, Azure CLI), and slash commands that automate the entire workflow from work item to pull request.

The slash commands assume Azure DevOps as the system of record:

- **Work items** — read, created, and updated via the Azure DevOps MCP server (`AB#1234` ids throughout)
- **Branches & pull requests** — created in Azure Repos and voted on / merged through Azure DevOps
- **Releases & deployments** — tracked as Azure DevOps iterations (`Release #N`) and tags; CD runs on Azure Pipelines
- **Wiki, test plans, advanced security alerts** — all surfaced through the same Azure DevOps MCP server

> **Not using Azure DevOps?** The Claude Code primitives (agents, hooks, memory) are still useful, but the slash commands and the deployment workflow won't apply out of the box — you'd need to rewrite the `/implement`, `/review`, `/deploy`, `/create-release`, `/deploy-release`, `/cherry-pick`, `/promote`, `/rollback`, `/track`, `/rework`, and `/resolve-feedback` commands against GitHub / GitLab / Jira / etc.

Every session Claude learns from your feedback and gets better at helping you specifically. The infrastructure is modular — install only what your project needs.

### What's Included

| Component | Count | Where Installed | Description |
|-----------|-------|----------------|-------------|
| **Global Agents** | 10 | `~/.claude/agents/` (your machine, all projects) | backend, frontend, legacy (Lucee/CFML), mockup, reviewer, test-runner, build-validator, lint-checker, azure-ops, security-auditor |
| **Project Agents** | 2 | `.claude/agents/` (in the project) | deployer, db-admin |
| **Hooks** | 9 | `.claude/hooks/` (in the project) | Secret blocker, sensitive data blocker (Bash + MCP + output), protected files, auto-format, test suggestions, UAT reminder, self-improve |
| **Slash Commands** | 24 | `.claude/commands/` (in the project) | `/implement`, `/review`, `/deep-review`, `/resolve-feedback`, `/fix-review`, `/deploy`, `/create-release`, `/deploy-release`, `/add-to-release`, `/cherry-pick`, `/promote`, `/rollback`, `/track`, `/plan-backlog`, `/plan-sprint`, `/quote-backlog`, `/cleanup-branches`, `/close-orphan-tasks`, `/quote`, `/explain`, `/create-work-item`, `/edit-work-item` |
| **MCP Servers** | Up to 6 | `.mcp.json` (in the project) | **Azure DevOps** (work items, repos, pipelines, wiki), Playwright, MongoDB/SQL/Postgres, Teams, Stripe, Azure CLI |
| **Workflow Template** | 1 | Appended to `CLAUDE.md` | Documents the full development process |
| **Settings** | 1 | `.claude/settings.json` (in the project) | Registers all hooks and MCP servers |

---

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- [Node.js](https://nodejs.org/) 18 or later
- An **Azure DevOps** organization with a project for work items, an Azure Repos Git repository, and (optionally) Azure Pipelines for CD
- An Azure DevOps Personal Access Token (PAT) — used by the Azure DevOps MCP server. Scopes needed: Work Items (read/write), Code (read/write), Build (read/execute), Wiki (read/write)

### Verify it works

```bash
npx @chris1807/claude-kit --help
```

You should see the help output. The package is published publicly on [npmjs.com](https://www.npmjs.com/package/@chris1807/claude-kit) — no authentication or `.npmrc` setup required.

---

## Installation

### How It Works

**Every install mode does two things:**
1. **Global agents** → installed to `~/.claude/agents/` (works across ALL your projects)
2. **Project files** → installed to the target project directory (agents, hooks, commands, MCP config, settings)

### Option 1: Interactive Install (Recommended)

Best for first-time setup or when you want to pick exactly what you need.

```bash
npx @chris1807/claude-kit init
```

You'll be asked:
1. **Target directory** — where is your project?
2. **Components** — checkboxes to pick which parts to install:
   - ☑ Project Agents (deployer, db-admin)
   - ☑ Hooks (secret blocker, auto-format, etc.)
   - ☑ Slash Commands (/implement, /review, /resolve-feedback, /deploy, /create-release, /deploy-release, /add-to-release, /cherry-pick, /promote, /rollback, /track, /cleanup-branches, /quote, /explain)
   - ☑ MCP Servers
   - ☑ Settings
   - ☑ CLAUDE.md Workflow
   - ☑ .gitignore Updates
3. **Database type** — MongoDB, SQL Server, Azure SQL, PostgreSQL, or None
4. **MCP servers** — pick which ones:
   - ☑ Playwright (browser testing)
   - ☑ Microsoft Teams (notifications)
   - ☐ Stripe (payments) — off by default
   - ☑ Azure CLI (infrastructure)
5. **Existing files** — for each file that already exists, choose overwrite or skip

### Option 2: Install to a Specific Project

Same as Option 1, but you specify the project path upfront:

```bash
npx @chris1807/claude-kit init /path/to/your/project
```

### Option 3: Install Everything (Minimal Prompts)

Installs all components. Only asks which database type (there's no sensible default).

```bash
npx @chris1807/claude-kit init --all
```

This installs:
- ✅ Global agents (backend, frontend, legacy, mockup, reviewer, test-runner, build-validator, lint-checker, azure-ops, security-auditor)
- ✅ Project agents (deployer, db-admin)
- ✅ All 9 hooks
- ✅ All 13 slash commands
- ✅ MCP servers: Playwright, Teams, Azure CLI (+ your DB choice)
- ✅ Settings, CLAUDE.md workflow, .gitignore
- ❌ Stripe (not included in --all, add via interactive mode)
- ⏭️ Skips files that are already identical
- 🔄 Overwrites files that have changed

### Option 4: Fully Automated (Zero Prompts)

Specify the database type as a flag — no prompts at all:

```bash
npx @chris1807/claude-kit init --all --db=mongo
npx @chris1807/claude-kit init --all --db=mssql
npx @chris1807/claude-kit init --all --db=azuresql
npx @chris1807/claude-kit init --all --db=postgres
```

You can also target a specific directory:
```bash
npx @chris1807/claude-kit init /path/to/project --all --db=mongo
```

### Option 5: Global Agents Only

Just installs the 13 global agents to `~/.claude/agents/`. No project files, no prompts.

```bash
npx @chris1807/claude-kit init --global-only
```

Use this when you just want the global agents on a new machine and will install project files separately per project.

### Re-Running the Installer

**Safe to run as many times as you want.** The installer:
- **Skips** files that are identical (no unnecessary changes)
- **Asks** before overwriting files that have changed (in interactive mode)
- **Overwrites** changed files silently (in `--all` mode)
- **Merges** MCP server configs (adds missing servers without removing existing ones)

### Installing on Additional Projects

Already installed on one project? Just run the same command for the next one:

```bash
npx @chris1807/claude-kit init /path/to/another/project
```

The installer automatically **skips global agents** that are already installed (they're identical) and only installs the project-specific files. You don't need `--global-only` or any special flag — it just works.

```
📦 Global Agents → ~/.claude/agents/
  = azure-ops.md (identical, skipped)       ← already installed, skipped
  = security-auditor.md (identical, skipped)
  = reviewer.md (identical, skipped)

📦 Project Agents → .claude/agents/         ← fresh install for this project
  ✓ deployer.md
  ✓ db-admin.md
  ...
```

---

## What Gets Installed

```
~/.claude/agents/                  ← Global (all projects)
├── backend.md                     # .NET/C# backend developer (Clean Architecture)
├── frontend.md                    # React/TypeScript frontend developer
├── legacy.md                      # Lucee/CFML legacy app developer (RBWO + others)
├── mockup.md                      # HTML mockup designer
├── reviewer.md                    # Code reviewer (read-only)
├── test-runner.md                 # Test executor — xUnit, Vitest, Playwright (read-only)
├── qa.md                          # Browser QA on a deployed environment (read-only)
├── build-validator.md             # Build checker (read-only)
├── lint-checker.md                # ESLint + dotnet format checker
├── azure-ops.md                   # Azure infrastructure management
└── security-auditor.md            # Security scanning (read-only)

your-project/                      ← Project-specific
├── .claude/
│   ├── agents/
│   │   ├── deployer.md            # Commit → push → deploy → monitor
│   │   └── db-admin.md            # Database queries and data management
│   │
│   ├── hooks/
│   │   ├── sensitive-data-blocker.sh       # BLOCKS mongosh queries for TIN/SSN/PII
│   │   ├── sensitive-data-mcp-blocker.sh   # BLOCKS MCP DB queries for TIN/SSN/PII
│   │   ├── sensitive-data-output-blocker.sh # BLOCKS output containing PII fields
│   │   ├── secret-blocker.sh      # BLOCKS hardcoded secrets before write
│   │   ├── protected-files.sh     # BLOCKS/warns on critical file edits
│   │   ├── auto-format.sh         # Auto-runs formatters after edits
│   │   ├── test-on-change.sh      # Suggests related tests after edits
│   │   ├── uat-reminder.sh        # Reminds to run UAT after features
│   │   └── self-improve.sh        # Saves learnings after each session
│   │
│   ├── commands/
│   │   ├── implement.md           # /implement AB#1234
│   │   ├── review.md              # /review 142
│   │   ├── deploy.md              # /deploy "commit message"
│   │   ├── create-release.md      # /create-release 23
│   │   ├── deploy-release.md      # /deploy-release 23 staging
│   │   ├── cherry-pick.md         # /cherry-pick AB#1234 prod
│   │   ├── promote.md             # /promote main dev
│   │   ├── rollback.md            # /rollback AB#1234 prod
│   │   ├── add-to-release.md      # /add-to-release 24 AB#4599
│   │   ├── track.md               # /track release 24
│   │   ├── cleanup-branches.md    # /cleanup-branches
│   │   ├── close-orphan-tasks.md  # /close-orphan-tasks
│   │   ├── quote.md               # /quote AB#1234
│   │   └── explain.md             # /explain AB#1234
│   │
│   └── settings.json              # Hook and MCP registration
│
├── .mcp.json                      # MCP server configuration
└── CLAUDE.md                      # Gets workflow section appended
```

---

## Usage

### Start Working

```bash
cd /path/to/your/project
claude
```

Verify MCP servers are connected:
```
/mcp
```

### Ultracode (multi-agent workflows)

The kit's agents normally run as **sequential delegation** — the main loop hands work to one specialist at a time through the `Task` tool. **Ultracode** is a separate, harness-level gear that authorizes the `Workflow` tool to fan out many agents in parallel under a deterministic script. The two compose: ultracode doesn't replace the pipeline, it parallelizes the parts that are embarrassingly parallel.

Ultracode is **opt-in**. It's on only when you type `ultracode` in a prompt, when a system-reminder confirms it, or when a slash command's instructions say to use `Workflow`. When it's off, everything runs the normal sequential way — nothing changes.

Only the **main Claude Code loop** and **slash commands** can call `Workflow`. Subagents (anything running under `Task`) cannot — so ultracode-scale fan-out is a main-loop / slash-command concern.

Kit operations that benefit from ultracode when it's on:

| Operation | Fan-out unit |
|-----------|--------------|
| `/plan-backlog` | one agent per Dev Ready story — analyze, point, and propose tasks in parallel |
| `/plan-sprint` | one agent per sprint item — analyze and propose tasks in parallel |
| `/quote-backlog` | one agent per swept item (stories in Design Approved, bugs in New) — completeness review, duplicate check, estimate in parallel |
| Backlog / board audits | one agent per work item — find stale, mislabeled, orphaned, or unestimated items |
| Multi-file or cross-layer review | one agent per file/dimension, then adversarial verify before reporting |
| Repo-wide sweeps (rename, dependency bump, pattern migration) | one agent per site, worktree-isolated |

Short, single-query operations (`/track`, `/explain`, `/close-orphan-tasks`) don't need ultracode — they're already one pass and gain nothing from fan-out. Reach for it when the work-list is large and the per-item work is independent.

### Implement a Work Item

```
/implement AB#1234
```

Claude automatically:
1. Reads the work item from Azure DevOps
2. **Summarizes and asks you to confirm** — shows title, description, acceptance criteria. Waits for you to agree or add context
3. Creates a feature branch based on work item type
4. Explores the codebase and **presents an implementation plan** — lists files to create, modify, and delete. Waits for your approval before writing any code
5. Implements using backend/frontend agents (only after plan approval)
6. Runs tests, linting, and build validation
7. Generates a UAT checklist from acceptance criteria
8. **Pauses for you to manually test**
9. Creates the PR after you confirm

**Implementing a whole Feature:** point `/implement` at a Feature work item and it implements the child User Stories in waves driven by the `Custom.Order` field — stories with the same order value are implemented in parallel (one agent per story, each in an isolated git worktree), and the next order value starts only after the previous wave is merged and green. Everything lands on one `feature/` branch with a single review, UAT pass, and PR that links every story.

### Review a Pull Request

```
/review 142
```

Claude automatically:
1. Reads the full PR diff
2. Reads the linked work item and checks all acceptance criteria
3. Reviews for Clean Architecture, security, missing tests, code quality
4. Posts inline comments on all findings
5. Posts a PR-level summary
6. Asks: "Approve, Request Changes, or skip the vote?"

### Deploy Changes

```
/deploy "Add payment export feature"
```

Claude automatically:
1. Runs pre-flight checks (dotnet build, tsc)
2. Stages and commits with the provided message
3. Pushes the current branch
4. Triggers the CD pipeline if on an environment branch (`dev`, `test`, `staging`, `prod`) — never on `main`, which has no pipeline

### Create a Release

```
/create-release 23
```

Claude automatically:
1. Asks which work items to include
2. Creates a `Release #23` iteration in Azure DevOps
3. Assigns and tags all work items with `release-23`

### Deploy a Release

```
/deploy-release 23 staging
```

Claude automatically:
1. Finds all work items in Release #23 and checks each against the environment's gate state (`Ready for Staging` here)
2. Cherry-picks their commits into `release/23-to-staging`
3. Creates a PR targeting the `staging` branch — merging it triggers the Staging pipeline
4. Links all work items to the PR
5. Asks who verifies each product group on Staging (`COM`, `PAY`, …) — candidates are the non-developer names already on those work items
6. Watches the PR and the Staging pipeline; once it's green, moves the work items to `Staging` and assigns them to the approved verifiers

The same command walks a release through `test` → `staging` → `prod`; with no environment given it picks the next one.

### Cherry-Pick Work Items

```
/cherry-pick AB#1234 AB#1235 prod
```

Cherry-picks specific work items to an environment without a formal release. Same gate check, same verifier question, and the same automatic state advance + assignment once the pipeline is green as `/deploy-release`. `main` is also a valid target — that's how a hot fix that went straight to `prod` is brought back into the compare branch.

### Promote an Environment

```
/promote main dev
/promote staging prod
/promote                  ← auto-detects from the current branch
```

Creates a PR to promote all code from one branch to the next in the chain (`main → dev → test → staging → prod`). Shows every commit and work item before confirming, gate-checks the work items, asks who verifies each product group, and advances and assigns them once the merge's pipeline is green. `main → dev` is the usual first hop after feature PRs merge — nothing has deployed before that.

### Rollback a Deployment

```
/rollback AB#1234 prod
/rollback last staging
```

Reverts specific commits or the last deployment on an environment. Creates a revert branch and PR.

### Add Work Items to a Release

```
/add-to-release 24 AB#4599 AB#4600
```

Adds work items to an existing release — assigns them to the iteration and tags them.

### Check Status

```
/track release 24
/track pipeline
/track AB#4521
/track staging
/track
```

Shows the status of a release, pipeline, work item, environment, or a high-level overview of everything.

### Quote a Work Item

```
/quote AB#1234
```

Displays a work item as a formatted blockquote — title, type, state, assignee, description, acceptance criteria, and child items. Useful for pasting into PR descriptions, Teams messages, or discussions.

### Explain a Work Item

```
/explain AB#1234
```

Reads a work item and explains it in plain language:
1. **Summary** — what the work item is about in 1–2 sentences
2. **What needs to happen** — acceptance criteria translated into concrete actions
3. **Why it matters** — business/user value
4. **Current status** — state, assignee, parent, child progress, linked PRs
5. **Scope & risks** — flags ambiguity, missing criteria, or large scope

### Clean Up Merged Branches

```
/cleanup-branches
/cleanup-branches --dry-run
```

Finds and deletes branches that have been fully merged. Protects environment branches. Use `--dry-run` to preview without deleting.

---

## Branching Strategy

### Target State (All Projects)

`main` is the **compare branch** — the default branch, the one feature PRs target, and the one every environment is compared against. **Merging into `main` deploys nothing.** Each environment has its own branch, and a PR merging into that branch is what triggers its CD pipeline:

| Branch | Environment | Deploys When |
|--------|-------------|-------------|
| `main` | — (compare / integration) | **Never** — a PR merging into `main` does not deploy |
| `dev` | Development | PR merged into `dev` |
| `test` | Test (QA) | PR merged into `test` |
| `staging` | Staging | PR merged into `staging` |
| `prod` | Production | PR merged into `prod` |

> **Note:** A project that hasn't migrated yet (e.g. one that still has only `main` and `develop`) keeps working — every command reads the project's Pipeline Configuration table and uses the branch you're on. No branch names are hardcoded.

### Work Item States Follow the Environments

Every environment has a work item state, and the promotion commands keep them in sync. The "Ready for …" states are human sign-offs; the commands never set them.

| Promotion | Gate (item should already be…) | State after the PR merges |
|-----------|-------------------------------|---------------------------|
| `main → dev` | `Code Review` | `Ready for Testing` |
| `dev → test` | `Ready for Testing` | `Testing` |
| `test → staging` | `Ready for Staging` (QA sign-off) | `Staging` |
| `staging → prod` | `Ready to Deploy` (stakeholder sign-off) | `Deployed` |

`/deploy-release`, `/cherry-pick`, and `/promote` check the gate before creating the PR, ask who verifies each product group while the PR is in review, then watch the PR and the environment's CD pipeline — on a green pipeline they set the state and the assignee together. A failed pipeline changes nothing. `/track` flags anything whose state lags the branch it's on.

### Branch Naming

When you run `/implement`, a branch is automatically created based on the Azure DevOps work item type:

| Work Item Type | Branch Prefix | Example |
|----------------|--------------|---------|
| Feature | `feature/` | `feature/AB#1234-add-payment-export` |
| User Story | `story/` | `story/AB#1235-user-can-view-history` |
| Bug | `bugfix/` | `bugfix/AB#1236-fix-login-redirect` |
| Hot Fix | `hotfix/` | `hotfix/AB#1237-fix-crash-on-submit` |
| (other) | `work/` | `work/AB#1238-update-dependencies` |

The branch is always created off the **current branch** — no assumptions are made about which branch you're on.

> **Note:** The Azure DevOps work item type is "Hot Fix" (two words), but the branch prefix and PR label use `hotfix` (one word, lowercase).

### Code Promotion Flow

Code flows through environments via PRs, never by direct push. Every merge **after** `main` deploys:

```
feature/AB#1234-... ──PR──▸ main ──PR──▸ dev ──PR──▸ test ──PR──▸ staging ──PR──▸ prod
   (work branch)          (compare,     (Dev)       (Test)        (Staging)      (Production)
                          no deploy)
```

---

## Development Workflow Guide

This section walks through the complete workflow from picking up a work item to deploying to production.

### Step 1: Implement a Work Item

Start by switching to your project's development branch and running `/implement`:

```bash
cd /path/to/your/project
claude
```

```
# Start from the compare branch
git checkout main

# Implement the work item
/implement AB#1234
```

Claude will:
1. Read the work item from Azure DevOps (extracts type, title, acceptance criteria)
2. **Summarize the work item** and ask you to confirm understanding. You can add context or corrections here
3. Create a branch automatically (e.g., `story/AB#1234-user-can-view-history`)
4. Explore the codebase and **present an implementation plan** showing which files will be created, modified, or deleted
5. **Wait for your approval** before writing any code
6. Implement using backend and/or frontend agents
7. Run all quality checks (build, lint, tests, review)
8. Generate a UAT checklist and **pause for you to manually test**
9. After you confirm "testing passed", create a PR targeting `main`, close the child Task with its hours, and move the work item to `Code Review`

The PR merges into `main`. **That merge deploys nothing** — `main` is the compare branch. The work reaches Dev when `main` is promoted:

```
/promote main dev
```

Merge that PR. Claude asks who verifies each product group on Dev, watches the Dev pipeline, and once it's green moves the work items to `Ready for Testing` and assigns them to those people.

### Step 2: Deploy Changes (Quick Commits)

For smaller changes that don't need the full `/implement` workflow:

```
/deploy "Fix typo in dashboard header"
```

This commits, pushes, and triggers the pipeline if you're on an environment branch (`dev`, `test`, `staging`, `prod`). On `main` or a feature branch it just pushes — nothing deploys until the work is promoted.

### Step 3: Group Work Items into a Release

Once multiple work items are merged to `main` and smoke-tested on Dev, group them into a release:

```
/create-release 23
```

Claude will:
1. Ask which work items to include — you can provide:
   - Specific IDs: `AB#1234, AB#1235, AB#1236`
   - A query: `all Ready for Testing user stories`
   - A state filter: `all items tagged sprint-5`
2. Show you the list and ask for confirmation
3. Create a `Release #23` iteration in Azure DevOps
4. Assign all work items to the iteration and tag them with `release-23`
5. Tell you how to deploy: `/deploy-release 23 test`, then `staging`, then `prod`

### Step 4: Deploy a Release to Test, then Staging

```
/deploy-release 23 test
```

Claude will:
1. Find all work items tagged `release-23` and check each is at the gate for Test (`Ready for Testing`)
2. Find their associated commits on `dev`
3. Create a release branch: `release/23-to-test`
4. Cherry-pick all commits for each work item
5. Create a PR from `release/23-to-test` → `test`
6. Link all work items to the PR
7. Ask who verifies each product group on Test
8. Watch the PR and the Test pipeline; on a green pipeline, move the work items to `Testing` and assign them to the approved verifiers

After the PR is reviewed and merged, the Test CD pipeline triggers automatically. QA tests there and sets each passing item to `Ready for Staging`; then `/deploy-release 23 staging` repeats the process (gate `Ready for Staging`, state after merge `Staging`).

### Step 5: Test on Staging

QA and stakeholders test on the Staging environment. If issues are found, fix them with `/implement` and add the fixes to the release.

### Step 6: Deploy a Release to Production

When stakeholders have verified on Staging and set the items to `Ready to Deploy`:

```
/deploy-release 23 prod
```

Same process — gate `Ready to Deploy`, cherry-picks from `staging` into a PR targeting `prod`. After merge the Production CD pipeline triggers; when it comes back green the items move to `Deployed` and are assigned to whoever you named for each product group.

### Selective Deployment

If staging has 5 user stories but only 3 are `Ready to Deploy`:

**Option A: Create a smaller release**
```
/create-release 24
```
Include only the 3 ready stories, then `/deploy-release 24 prod`.

**Option B: Cherry-pick specific items**
```
/cherry-pick AB#1234 AB#1235 AB#1236 prod
```
This cherry-picks just those 3 work items without creating a formal release.

### Promoting Without a Release

To promote **all** code from one branch to the next (no cherry-picking):

```
/promote main dev
/promote staging prod
```

This creates a PR from the source branch to the next one in the chain containing everything. `main → dev` is the everyday first hop; `staging → prod` is for when everything on staging is approved.

You can also auto-detect the next environment:
```
/promote
```
If you're on `main`, it auto-detects `main → dev`; on `staging`, `staging → prod`.

### Hot Fix Workflow

For critical production issues:

1. Switch to the production branch:
   ```
   git checkout prod
   ```
2. Run `/implement` with the Hot Fix work item:
   ```
   /implement AB#9999
   ```
3. Claude creates a `hotfix/AB#9999-fix-crash-on-submit` branch
4. Automated checks still run (build, lint, tests, review)
5. **Manual UAT is skipped** — you get an abbreviated confirmation instead
6. PR targets `prod` directly with a `hotfix` label — merging it deploys straight to production
7. Then bring the fix back to `main` (a second PR from the same branch, or `/cherry-pick AB#9999 main`) so the next `main → dev` promotion doesn't overwrite it

### Rollback a Deployment

If a deployment causes issues:

**Revert specific work items:**
```
/rollback AB#1234 prod
```

**Revert the most recent deployment:**
```
/rollback last staging
```

Claude will:
1. Find the commits to revert
2. Create a revert branch (e.g., `revert/2026-09-06-on-prod`)
3. Run `git revert` on each commit
4. Run pre-flight checks on the reverted code
5. Create a PR targeting the environment branch

Merge the PR to deploy the rollback. Work item states are left alone — Claude tells you which items were reverted so you can decide. If the reverted commits are also on `main`, the next promotion brings them back unless the revert is applied there too.

### Code Review

For any open PR:

```
/review 142
```

Claude reviews for:
- Clean Architecture boundaries (Domain has no infrastructure dependencies)
- Tenant/organizationId enforcement on all database queries
- Missing unit or integration tests for new code
- `any` types in TypeScript (should be properly typed)
- Security issues (OWASP Top 10, hardcoded secrets)
- Acceptance criteria coverage from the linked work item

---

## Slash Commands Reference

| Command | Usage | What It Does |
|---------|-------|-------------|
| `/implement` | `/implement AB#1234` | Read work item → summarize → approve plan → implement → quality checks → UAT → PR. On a Feature: implements child stories in `Custom.Order` waves, same-order stories in parallel |
| `/review` | `/review 142` | Full code review on a PR with inline comments |
| `/deep-review` | `/deep-review 142` | Deep, Ultracode-orchestrated review: checks out the branch, builds/tests it, verifies every requirement, checks for regressions, flags out-of-scope changes, then comments + votes |
| `/resolve-feedback` | `/resolve-feedback 142` | Address unresolved PR comment threads, push fixes, reply + resolve threads |
| `/fix-review` | `/fix-review 142` | Fix everything flagged on a PR — human reviewer comments and automated `/review` findings alike: implement in severity order, validate, push, resolve threads |
| `/deploy` | `/deploy "message"` | Commit, push, trigger pipeline if on an environment branch (`dev`/`test`/`staging`/`prod`) — never on `main` |
| `/create-release` | `/create-release 23` | Group work items into Release #23 iteration with tags |
| `/deploy-release` | `/deploy-release 23 staging` | Gate-check → cherry-pick release work items to environment via PR → ask who verifies → advance + assign on a green pipeline |
| `/add-to-release` | `/add-to-release 24 AB#4599` | Add work items to an existing release |
| `/cherry-pick` | `/cherry-pick AB#1234 AB#1235 prod` | Gate-check → cherry-pick specific work items to environment via PR → ask who verifies → advance + assign on a green pipeline |
| `/promote` | `/promote main dev` | PR to promote all code to the next branch in the chain (`main → dev → test → staging → prod`) → ask who verifies → advance + assign on a green pipeline |
| `/rollback` | `/rollback AB#1234 prod` | Revert specific commits on an environment via PR |
| `/track` | `/track release 24` | Check status of a release, pipeline, work item, or environment; flags work items whose state lags their environment |
| `/qa` | `/qa AB#1234 [env]` | Verify the item is fully deployed with a green pipeline → open the app in a real browser → sign in as a test account → full regression of the screens the story touched → pass/fail comment on the work item (never a state change). Environments: `local`, `dev`, `test`, `staging` |
| `/plan-backlog` | `/plan-backlog [project]` | Sweep backlog for Dev Ready stories with points and no tasks → propose one child task with hours per story |
| `/plan-sprint` | `/plan-sprint [project]` | Sweep the current sprint for stories/bugs with no child tasks → propose one child task with hours per item |
| `/quote-backlog` | `/quote-backlog [project]` | Sweep backlog for unpointed items ready to estimate — stories in `Design Approved`, bugs in `New` (bugs have no design states) → review completeness, check for duplicates, suggest rewrites, propose points + creator comments (10 at a time, approval-gated). Also audits the drop-out queue — tagged bugs and stories bounced to Design Review — for items whose creator answered but which nobody returned to the sweep |
| `/quote` | `/quote AB#1234` | Estimate a work item in story points (senior-calibrated Fibonacci rubric) |
| `/explain` | `/explain AB#1234` | Summarize and explain a work item in plain language |
| `/create-work-item` | `/create-work-item [description]` | Interactively draft and create a Feature, Bug, User Story, or Hot Fix — proposes story points (user must agree), creates pointed items in Dev Ready; on a Feature, also drafts its child stories with `Custom.Order` waves |
| `/edit-work-item` | `/edit-work-item AB#1234 [what to change]` | Revise an existing work item field-by-field. On a Feature, cascades into its child stories — updates, adds, retires, and re-sequences `Custom.Order` waves — with a safety gate on anything already past Dev Ready |
| `/cleanup-branches` | `/cleanup-branches` | Delete merged feature/work branches |
| `/close-orphan-tasks` | `/close-orphan-tasks --dry-run` | Close open Tasks whose parent is Ready to Deploy / Deployed / Closed |

---

## Hooks

These run automatically — no action needed:

| When | Hook | What It Does |
|------|------|-------------|
| **Before** any Bash command | `sensitive-data-blocker.sh` | Blocks `mongosh` commands that reference sensitive PII fields (TIN, SSN, bank accounts). **Blocks the command.** |
| **Before** any MCP database tool | `sensitive-data-mcp-blocker.sh` | Blocks MongoDB/MSSQL/Postgres MCP tool calls that reference PII fields. **Blocks the call.** |
| **After** any Bash/MCP/Read/Grep | `sensitive-data-output-blocker.sh` | Scans output for PII field names in JSON, C#, YAML formats — catches broad queries, seed data, test fixtures, log files, and git diffs. **Blocks the output.** |
| **Before** any file write | `secret-blocker.sh` | Scans for hardcoded credentials (MongoDB URIs, AWS keys, Stripe keys, passwords). **Blocks the write.** |
| **Before** any file edit | `protected-files.sh` | Blocks edits to production/staging configs. Warns on critical files (CLAUDE.md, pipelines, Program.cs). |
| **After** any file edit | `auto-format.sh` | Runs `dotnet format` on .cs files, `eslint --fix` on .ts/.tsx files |
| **After** any file edit | `test-on-change.sh` | Suggests the relevant test command for the modified file |
| **When Claude stops** | `uat-reminder.sh` | Reminds to run UAT if a feature was implemented |
| **When Claude stops** | `self-improve.sh` | Prompts Claude to save learnings to memory for next time |

---

## Environment Variables

Each team member sets their own. **Never commit these.**

Add to `~/.zshrc` (Mac) or System Environment Variables (Windows):

```bash
# MongoDB (if your project uses MongoDB)
export MONGODB_CONNECTION_STRING="mongodb+srv://user:password@cluster.mongodb.net/"

# SQL Server (if your project uses SQL Server or Azure SQL)
export MSSQL_CONNECTION_STRING="Server=localhost;Database=MyDb;User Id=sa;Password=...;"

# PostgreSQL (if your project uses PostgreSQL)
export POSTGRES_CONNECTION_STRING="postgresql://user:password@localhost:5432/mydb"

# Stripe (if your project uses Stripe payments)
export STRIPE_SECRET_KEY="sk_test_..."

# Azure CLI (no env var needed — just log in)
az login

# QA test accounts (required for /qa — browser testing on a deployed environment).
# One pair per role. The variable NAMES go in your project's `## Environment URLs`
# section; the VALUES live only here. Use throwaway least-privilege QA accounts.
export COMPASS_QA_ADMIN_USERNAME="qa-admin@example.com"
export COMPASS_QA_ADMIN_PASSWORD="..."

# Microsoft Teams (no env vars needed — uses Microsoft Graph device-code auth;
# first invocation prints a code + URL to sign in)
```

### Setting Up the Teams MCP Server

1. Go to [Azure Portal > App Registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps)
2. Click **New Registration** → name it "Claude Code Teams Bot"
3. **API Permissions** → Add Microsoft Graph:
   - `ChannelMessage.Send`
   - `ChannelMessage.Read.All`
   - `Chat.ReadWrite`
   - `Team.ReadBasic.All`
4. **Certificates & Secrets** → Create a new client secret
5. Copy the Tenant ID, Client ID, and Client Secret
6. Set the three `TEAMS_*` environment variables above

---

## Memory System

Claude maintains persistent memory across sessions in `~/.claude/projects/.../memory/`. The self-improvement hook prompts Claude to save learnings after each session.

| Memory Type | Purpose | Example |
|-------------|---------|---------|
| **user** | Who you are, preferences, expertise | "Senior .NET dev, prefers terse responses" |
| **feedback** | What to do / avoid (self-improving) | "Never enable 'Complete associated work items' when merging a PR" |
| **project** | Decisions, priorities, blockers | "Using Stripe instead of Dwolla because..." |
| **reference** | URLs, credentials, external resources | "Staging URL: https://..." |

### Setting Up Your Memory

After installing, start a Claude Code session and say:
```
Set up my memory profile. I'm [your name], a [your role] at [your company].
I work on [your projects]. I prefer [your preferences].
```

Claude creates the initial memory files. Each subsequent session adds to them automatically.

---

## Customization

### Adding Custom Agents

Create `.claude/agents/your-agent.md` in your project:

```markdown
---
name: your-agent
description: What this agent does
tools:
  - Bash
  - Read
  - Write
---

Instructions for the agent...
```

### Adding Custom Hooks

1. Create `.claude/hooks/your-hook.sh` and make it executable
2. Add it to `.claude/settings.json` under PreToolUse, PostToolUse, or Stop

### Adding Custom Slash Commands

Create `.claude/commands/your-command.md`:

```markdown
Do something with $ARGUMENTS.

1. Step one
2. Step two
```

Use it: `/your-command some-argument`

### Removing Components

Delete any agent, hook, command, or MCP server you don't need. Everything works independently.

---

## Updating

When the infrastructure package is updated:

```bash
# npx always fetches the latest version
npx @chris1807/claude-kit init /path/to/project
```

The installer detects existing files and asks whether to overwrite or skip each one.

### Publishing Updates (Maintainers Only)

```bash
cd claude-kit

# Make your changes, then bump the version
npm version patch    # 2.0.0 → 2.0.1

# Push the tag — GitHub Actions publishes to npm automatically
git push && git push --tags
```

> The `.github/workflows/publish.yml` workflow runs on any pushed `v*` tag and publishes to npm using the `NPM_TOKEN` repo secret. You should not run `npm publish` from a dev machine.

---

## Security

- **No secrets in the repo** — `.mcp.json` only contains `${ENV_VAR}` references
- **Sensitive data blocker hooks (4 layers)** — blocks database queries referencing TIN, SSN, bank account numbers, or other PII fields before execution (Bash + MCP), and scans all output (Bash, MCP, Read, Grep) for PII field names. Even encrypted values are never exposed. CLAUDE.md policy is injected at the top of every project
- **Secret blocker hook** — automatically blocks writes containing hardcoded credentials
- **Protected files hook** — prevents edits to production/staging configs
- **`.claude/settings.local.json`** is gitignored — personal permissions stay private
- **Public npm package** — published from a GitHub Actions workflow gated on a tag-version match check

---

## Troubleshooting

### `npm ERR! 404 Not Found`

If `npx @chris1807/claude-kit` reports 404, your local npm registry may be set to a private feed that overrides the public one. Check with `npm config get registry` — it should be `https://registry.npmjs.org/`.

### Hooks not running

Verify the settings file is loaded:
```
claude
/config
```
Check that `.claude/settings.json` shows your hooks.

### MCP server not connecting

Check that the environment variable is set:
```bash
echo $MONGODB_CONNECTION_STRING   # Should show your connection string
echo $STRIPE_SECRET_KEY           # Should show sk_test_...
az account show                   # Should show your Azure subscription
```

---

## Support

- **Issues:** [github.com/Christopher-Waters/claude-kit/issues](https://github.com/Christopher-Waters/claude-kit/issues)
- **Source:** [github.com/Christopher-Waters/claude-kit](https://github.com/Christopher-Waters/claude-kit)

## License

MIT
