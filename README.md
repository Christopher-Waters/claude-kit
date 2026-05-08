# Claude Kit

> A starter kit for [Claude Code](https://claude.ai/code) — agents, hooks, MCP servers, slash commands, and workflow automation, installed into any project with a single `npx` command.

[![npm](https://img.shields.io/npm/v/@chris1807/claude-kit)](https://www.npmjs.com/package/@chris1807/claude-kit)

---

## About

This package installs a complete AI development infrastructure into any project. It includes specialized agents that handle specific tasks (deployment, database ops, code review), security hooks that prevent mistakes automatically, MCP server connections to your tools (databases, Teams, Stripe, Azure CLI), and slash commands that automate your entire workflow from work item to pull request.

Every session Claude learns from your feedback and gets better at helping you specifically. The infrastructure is modular — install only what your project needs.

### What's Included

| Component | Count | Where Installed | Description |
|-----------|-------|----------------|-------------|
| **Global Agents** | 13 | `~/.claude/agents/` (your machine, all projects) | backend, frontend, legacy (Lucee/CFML), manager, mockup, reviewer, test-runner, build-validator, lint-checker, uat-generator, azure-ops, security-auditor, api-tester |
| **Project Agents** | 3 | `.claude/agents/` (in the project) | deployer, db-admin, devops-tracker |
| **Hooks** | 9 | `.claude/hooks/` (in the project) | Secret blocker, sensitive data blocker (Bash + MCP + output), protected files, auto-format, test suggestions, UAT reminder, self-improve |
| **Slash Commands** | 13 | `.claude/commands/` (in the project) | `/implement`, `/review`, `/deploy`, `/create-release`, `/deploy-release`, `/add-to-release`, `/cherry-pick`, `/promote`, `/rollback`, `/status`, `/cleanup-branches`, `/quote`, `/explain` |
| **MCP Servers** | Up to 6 | `.mcp.json` (in the project) | Playwright, MongoDB/SQL/Postgres, Teams, Stripe, Azure CLI |
| **Workflow Template** | 1 | Appended to `CLAUDE.md` | Documents the full development process |
| **Settings** | 1 | `.claude/settings.json` (in the project) | Registers all hooks and MCP servers |

---

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- [Node.js](https://nodejs.org/) 18 or later

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
   - ☑ Project Agents (deployer, db-admin, devops-tracker)
   - ☑ Hooks (secret blocker, auto-format, etc.)
   - ☑ Slash Commands (13 commands — /implement, /review, /deploy, /create-release, /deploy-release, /add-to-release, /cherry-pick, /promote, /rollback, /status, /cleanup-branches, /quote, /explain)
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
- ✅ Global agents (backend, frontend, legacy, manager, mockup, reviewer, test-runner, build-validator, lint-checker, uat-generator, azure-ops, security-auditor, api-tester)
- ✅ Project agents (deployer, db-admin, devops-tracker)
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
  = api-tester.md (identical, skipped)

📦 Project Agents → .claude/agents/         ← fresh install for this project
  ✓ deployer.md
  ✓ db-admin.md
  ✓ devops-tracker.md
  ...
```

---

## What Gets Installed

```
~/.claude/agents/                  ← Global (all projects)
├── backend.md                     # .NET/C# backend developer (Clean Architecture)
├── frontend.md                    # React/TypeScript frontend developer
├── legacy.md                      # Lucee/CFML legacy app developer (RBWO + others)
├── manager.md                     # Workflow orchestrator (delegates to other agents)
├── mockup.md                      # HTML mockup designer
├── reviewer.md                    # Code reviewer (read-only)
├── test-runner.md                 # Test executor — xUnit, Vitest, Playwright (read-only)
├── build-validator.md             # Build checker (read-only)
├── lint-checker.md                # ESLint + dotnet format checker
├── uat-generator.md               # UAT checklist generator (read-only)
├── azure-ops.md                   # Azure infrastructure management
├── security-auditor.md            # Security scanning (read-only)
└── api-tester.md                  # API endpoint testing

your-project/                      ← Project-specific
├── .claude/
│   ├── agents/
│   │   ├── deployer.md            # Commit → push → deploy → monitor
│   │   ├── db-admin.md            # Database queries and data management
│   │   └── devops-tracker.md      # Azure DevOps work item management
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
│   │   ├── cherry-pick.md         # /cherry-pick AB#1234 production
│   │   ├── promote.md             # /promote staging production
│   │   ├── rollback.md            # /rollback AB#1234 production
│   │   ├── add-to-release.md      # /add-to-release 24 AB#4599
│   │   ├── status.md              # /status release 24
│   │   ├── cleanup-branches.md    # /cleanup-branches
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
4. Triggers the CD pipeline if on an environment branch

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
1. Finds all work items in Release #23
2. Cherry-picks their commits into `release/23-to-staging`
3. Creates a PR targeting the staging branch
4. Links all work items to the PR

### Cherry-Pick Work Items

```
/cherry-pick AB#1234 AB#1235 production
```

Cherry-picks specific work items to an environment without a formal release.

### Promote an Environment

```
/promote staging production
```

Creates a PR to promote all code from staging to production. Shows a summary of all included commits before confirming.

### Rollback a Deployment

```
/rollback AB#1234 production
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
/status release 24
/status pipeline
/status AB#4521
/status staging
/status
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

Every project should converge to this standard. Each long-lived branch maps to an Azure subscription and environment:

| Branch | Azure Subscription | Environment | Deploys When |
|--------|-------------------|-------------|-------------|
| `develop` | Dev | Development | PR merged into `develop` |
| `staging` | Staging | Staging | PR merged into `staging` |
| `main` | Production | Production | PR merged into `main` (with approval gate) |

> **Note:** Some projects are not yet in sync — they may use `master` instead of `main`, or lack a `staging` branch. All commands work dynamically with whatever branch you're on. No branch names are hardcoded.

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

Code flows through environments via PRs, never by direct push:

```
feature/AB#1234-... ──PR──▸ develop ──PR──▸ staging ──PR──▸ main
   (work branch)            (Dev)          (Staging)      (Production)
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
# Switch to the develop branch first
git checkout develop

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
9. After you confirm "testing passed", create a PR targeting `develop`

The PR merges into `develop`, which triggers the Dev environment CD pipeline.

### Step 2: Deploy Changes (Quick Commits)

For smaller changes that don't need the full `/implement` workflow:

```
/deploy "Fix typo in dashboard header"
```

This commits, pushes, and triggers the pipeline if you're on an environment branch. If you're on a feature branch, it just pushes — the pipeline triggers on PR merge.

### Step 3: Group Work Items into a Release

Once multiple work items are merged to `develop` and tested in Dev, group them into a release:

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
5. Tell you how to deploy: `/deploy-release 23 staging` or `/deploy-release 23 production`

### Step 4: Deploy a Release to Staging

```
/deploy-release 23 staging
```

Claude will:
1. Find all work items tagged `release-23`
2. Find their associated commits on the `develop` branch
3. Create a release branch: `release/23-to-staging`
4. Cherry-pick all commits for each work item
5. Create a PR from `release/23-to-staging` → `staging`
6. Link all work items to the PR

After the PR is reviewed and merged, the Staging CD pipeline triggers automatically.

### Step 5: Test on Staging

QA and stakeholders test on the Staging environment. If issues are found, fix them with `/implement` and add the fixes to the release.

### Step 6: Deploy a Release to Production

When staging testing passes:

```
/deploy-release 23 production
```

Same process — cherry-picks the release's commits to a PR targeting the production branch. After merge, the Production CD pipeline triggers (with approval gate).

### Selective Deployment

If staging has 5 user stories but only 3 are ready for production:

**Option A: Create a smaller release**
```
/create-release 24
```
Include only the 3 ready stories, then `/deploy-release 24 production`.

**Option B: Cherry-pick specific items**
```
/cherry-pick AB#1234 AB#1235 AB#1236 production
```
This cherry-picks just those 3 work items without creating a formal release.

### Promoting Without a Release

To promote **all** code from one environment to the next (no cherry-picking):

```
/promote staging production
```

This creates a PR from `staging` → production branch containing everything. Use this when all staging code is ready for production.

You can also auto-detect the next environment:
```
/promote
```
If you're on the `staging` branch, it auto-detects `staging → production`.

### Hot Fix Workflow

For critical production issues:

1. Switch to the production branch:
   ```
   git checkout main
   ```
2. Run `/implement` with the Hot Fix work item:
   ```
   /implement AB#9999
   ```
3. Claude creates a `hotfix/AB#9999-fix-crash-on-submit` branch
4. Automated checks still run (build, lint, tests, review)
5. **Manual UAT is skipped** — you get an abbreviated confirmation instead
6. PR targets the production branch directly with a `hotfix` label

### Rollback a Deployment

If a deployment causes issues:

**Revert specific work items:**
```
/rollback AB#1234 production
```

**Revert the most recent deployment:**
```
/rollback last staging
```

Claude will:
1. Find the commits to revert
2. Create a revert branch (e.g., `revert/2026-03-21-on-production`)
3. Run `git revert` on each commit
4. Run pre-flight checks on the reverted code
5. Create a PR targeting the environment branch

Merge the PR to deploy the rollback.

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
| `/implement` | `/implement AB#1234` | Read work item → summarize → approve plan → implement → quality checks → UAT → PR |
| `/review` | `/review 142` | Full code review on a PR with inline comments |
| `/deploy` | `/deploy "message"` | Commit, push, trigger pipeline if on environment branch |
| `/create-release` | `/create-release 23` | Group work items into Release #23 iteration with tags |
| `/deploy-release` | `/deploy-release 23 staging` | Cherry-pick release work items to environment via PR |
| `/add-to-release` | `/add-to-release 24 AB#4599` | Add work items to an existing release |
| `/cherry-pick` | `/cherry-pick AB#1234 AB#1235 production` | Cherry-pick specific work items to environment via PR |
| `/promote` | `/promote staging production` | PR to promote all code between environments |
| `/rollback` | `/rollback AB#1234 production` | Revert specific commits on an environment via PR |
| `/status` | `/status release 24` | Check status of a release, pipeline, work item, or environment |
| `/quote` | `/quote AB#1234` | Display a work item as a formatted blockquote |
| `/explain` | `/explain AB#1234` | Summarize and explain a work item in plain language |
| `/cleanup-branches` | `/cleanup-branches` | Delete merged feature/work branches |

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

# Microsoft Teams (for team notifications and messages)
export TEAMS_TENANT_ID="your-azure-ad-tenant-id"
export TEAMS_CLIENT_ID="your-app-registration-client-id"
export TEAMS_CLIENT_SECRET="your-client-secret"

# Stripe (if your project uses Stripe payments)
export STRIPE_SECRET_KEY="sk_test_..."

# Azure CLI (no env var needed — just log in)
az login
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
| **feedback** | What to do / avoid (self-improving) | "Always push to both main and develop" |
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
