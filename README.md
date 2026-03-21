# Care Solutions AI Infrastructure

> Personal AI Infrastructure for [Claude Code](https://claude.ai/code) — an internal package that gives every Care Solutions team member a standardized, AI-powered development experience.

**Private package.** Published to the Care Solutions Azure DevOps Artifacts npm feed. Only organization members can install it.

---

## About

This package installs a complete AI development infrastructure into any project. It includes specialized agents that handle specific tasks (deployment, database ops, code review), security hooks that prevent mistakes automatically, MCP server connections to your tools (Azure DevOps, MongoDB, Teams, Stripe), and slash commands that automate your entire workflow from work item to pull request.

Every session Claude learns from your feedback and gets better at helping you specifically. The infrastructure is modular — install only what your project needs.

### What's Included

| Component | Count | Where Installed | Description |
|-----------|-------|----------------|-------------|
| **Global Agents** | 3 | `~/.claude/agents/` (your machine, all projects) | azure-ops, security-auditor, api-tester |
| **Project Agents** | 3 | `.claude/agents/` (in the project) | deployer, db-admin, devops-tracker |
| **Hooks** | 7 | `.claude/hooks/` (in the project) | Secret blocker, sensitive data blocker, protected files, auto-format, test suggestions, UAT reminder, self-improve |
| **Slash Commands** | 2 | `.claude/commands/` (in the project) | `/implement` (work item → PR), `/review` (automated code review) |
| **MCP Servers** | Up to 6 | `.mcp.json` (in the project) | Playwright, MongoDB/SQL/Postgres, Teams, Stripe, Azure CLI |
| **Workflow Template** | 1 | Appended to `CLAUDE.md` | Documents the full development process |
| **Settings** | 1 | `.claude/settings.json` (in the project) | Registers all hooks and MCP servers |

---

## First-Time Setup (One Time Per Machine)

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- [Node.js](https://nodejs.org/) 18 or later
- Access to the Care Solutions Azure DevOps organization

### Step 1: Authenticate with the npm feed

```bash
# Add our private registry for @caresolutions packages
echo "@caresolutions:registry=https://pkgs.dev.azure.com/caresolutionsinc/_packaging/caresolutionsinc/npm/registry/" >> ~/.npmrc

# Authenticate (follow the prompts — use your Azure DevOps credentials)
npm login --registry=https://pkgs.dev.azure.com/caresolutionsinc/_packaging/caresolutionsinc/npm/registry/
```

> **Windows users:** If `npm login` doesn't work, install the Azure DevOps auth helper:
> ```bash
> npm install -g vsts-npm-auth
> vsts-npm-auth -config .npmrc
> ```

### Step 2: Verify it works

```bash
npx @caresolutions/ai-infrastructure --help
```

You should see the help output. If you get a 401 or 403 error, re-run `npm login` from Step 1.

---

## Installation

### How It Works

**Every install mode does two things:**
1. **Global agents** → installed to `~/.claude/agents/` (works across ALL your projects)
2. **Project files** → installed to the target project directory (agents, hooks, commands, MCP config, settings)

### Option 1: Interactive Install (Recommended)

Best for first-time setup or when you want to pick exactly what you need.

```bash
npx @caresolutions/ai-infrastructure init
```

You'll be asked:
1. **Target directory** — where is your project?
2. **Components** — checkboxes to pick which parts to install:
   - ☑ Project Agents (deployer, db-admin, devops-tracker)
   - ☑ Hooks (secret blocker, auto-format, etc.)
   - ☑ Slash Commands (/implement, /review)
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
npx @caresolutions/ai-infrastructure init /path/to/your/project
```

### Option 3: Install Everything (Minimal Prompts)

Installs all components. Only asks which database type (there's no sensible default).

```bash
npx @caresolutions/ai-infrastructure init --all
```

This installs:
- ✅ Global agents (azure-ops, security-auditor, api-tester)
- ✅ Project agents (deployer, db-admin, devops-tracker)
- ✅ All 6 hooks
- ✅ Both slash commands (/implement, /review)
- ✅ MCP servers: Playwright, Teams, Azure CLI (+ your DB choice)
- ✅ Settings, CLAUDE.md workflow, .gitignore
- ❌ Stripe (not included in --all, add via interactive mode)
- ⏭️ Skips files that are already identical
- 🔄 Overwrites files that have changed

### Option 4: Fully Automated (Zero Prompts)

Specify the database type as a flag — no prompts at all:

```bash
npx @caresolutions/ai-infrastructure init --all --db=mongo
npx @caresolutions/ai-infrastructure init --all --db=mssql
npx @caresolutions/ai-infrastructure init --all --db=azuresql
npx @caresolutions/ai-infrastructure init --all --db=postgres
```

You can also target a specific directory:
```bash
npx @caresolutions/ai-infrastructure init /path/to/project --all --db=mongo
```

### Option 5: Global Agents Only

Just installs the 3 global agents to `~/.claude/agents/`. No project files, no prompts.

```bash
npx @caresolutions/ai-infrastructure init --global-only
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
npx @caresolutions/ai-infrastructure init /path/to/another/project
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
│   │   ├── sensitive-data-blocker.sh # BLOCKS DB queries for TIN/SSN/PII
│   │   ├── secret-blocker.sh      # BLOCKS hardcoded secrets before write
│   │   ├── protected-files.sh     # BLOCKS/warns on critical file edits
│   │   ├── auto-format.sh         # Auto-runs formatters after edits
│   │   ├── test-on-change.sh      # Suggests related tests after edits
│   │   ├── uat-reminder.sh        # Reminds to run UAT after features
│   │   └── self-improve.sh        # Saves learnings after each session
│   │
│   ├── commands/
│   │   ├── implement.md           # /implement AB#1234
│   │   └── review.md              # /review 142
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
2. Explores the codebase and plans the approach
3. Delegates to backend/frontend agents to implement
4. Runs tests, linting, and build validation
5. Generates a UAT checklist from acceptance criteria
6. **Pauses for you to manually test**
7. Creates the PR after you confirm

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

### For Senior Devs / Tech Leads

Use `/review` on any PR for automated code review:
```
/review 142
```

The review checks:
- Clean Architecture boundaries (Domain has no infrastructure dependencies)
- Tenant/organizationId enforcement on all database queries
- Missing unit or integration tests for new code
- `any` types in TypeScript (should be properly typed)
- Security issues (OWASP Top 10, hardcoded secrets)
- Acceptance criteria coverage from the linked work item

---

## Hooks

These run automatically — no action needed:

| When | Hook | What It Does |
|------|------|-------------|
| **Before** any Bash command | `sensitive-data-blocker.sh` | Blocks database queries that reference sensitive PII fields (TIN, SSN, bank accounts). **Blocks the command.** |
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
Set up my memory profile. I'm [your name], a [your role] at Care Solutions.
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
npx @caresolutions/ai-infrastructure init /path/to/project
```

The installer detects existing files and asks whether to overwrite or skip each one.

### Publishing Updates (Maintainers Only)

```bash
cd care-solutions-ai

# Make your changes, then bump the version
npm version patch    # 1.0.1 → 1.0.2

# Publish to the private feed
npm run publish:feed

# Push to repo
git push && git push --tags
```

---

## Security

- **No secrets in the repo** — `.mcp.json` only contains `${ENV_VAR}` references
- **Sensitive data blocker hook** — blocks database queries that reference TIN, SSN, bank account numbers, or other PII fields (even encrypted values are never exposed)
- **Secret blocker hook** — automatically blocks writes containing hardcoded credentials
- **Protected files hook** — prevents edits to production/staging configs
- **`.claude/settings.local.json`** is gitignored — personal permissions stay private
- **Private npm feed** — only Care Solutions Azure DevOps org members can install

---

## Troubleshooting

### `npm ERR! 401 Unauthorized` when running npx

Re-authenticate with the npm feed:
```bash
npm login --registry=https://pkgs.dev.azure.com/caresolutionsinc/_packaging/caresolutionsinc/npm/registry/
```

### `npm ERR! 404 Not Found`

Make sure the registry is configured:
```bash
echo "@caresolutions:registry=https://pkgs.dev.azure.com/caresolutionsinc/_packaging/caresolutionsinc/npm/registry/" >> ~/.npmrc
```

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

- **Questions:** Ask in the #engineering Teams channel
- **Issues:** Create a work item in the [Care Solutions AI](https://dev.azure.com/caresolutionsinc/Care%20Solutions%20AI) project
- **Source:** https://dev.azure.com/caresolutionsinc/Care%20Solutions%20AI/_git/Care%20Solutions%20AI

## License

MIT — Care Solutions internal use.
