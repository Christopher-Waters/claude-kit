# Care Solutions AI Infrastructure

> Personal AI Infrastructure for [Claude Code](https://claude.ai/code) — an internal package that gives every Care Solutions team member a standardized, AI-powered development experience.

**Private package.** Published to the Care Solutions Azure DevOps Artifacts npm feed. Only organization members can install it.

---

## About

This package installs a complete AI development infrastructure into any project. It includes specialized agents that handle specific tasks (deployment, database ops, code review), security hooks that prevent mistakes automatically, MCP server connections to your tools (Azure DevOps, MongoDB, Teams, Stripe), and slash commands that automate your entire workflow from work item to pull request.

Every session Claude learns from your feedback and gets better at helping you specifically. The infrastructure is modular — install only what your project needs.

### What's Included

| Component | Count | Description |
|-----------|-------|-------------|
| **Project Agents** | 3 | deployer (CI/CD), db-admin (MongoDB), devops-tracker (work items) |
| **Global Agents** | 3 | azure-ops (infrastructure), security-auditor (scanning), api-tester (endpoint testing) |
| **Hooks** | 6 | Secret blocker, protected files, auto-format, test suggestions, UAT reminder, self-improve |
| **MCP Servers** | 6 | Azure DevOps, Playwright, MongoDB/SQL/Postgres, Teams, Stripe, Azure CLI |
| **Slash Commands** | 2 | `/implement` (work item → code → tests → PR), `/review` (automated PR review) |
| **Workflow Template** | 1 | Appended to CLAUDE.md — documents the full development process |
| **Memory System** | Template | Self-improving context that gets smarter every session |

---

## First-Time Setup (One Time Per Machine)

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- [Node.js](https://nodejs.org/) 18 or later
- Access to the Care Solutions Azure DevOps organization

### Step 1: Authenticate with the npm feed

You need to connect npm to our private Azure DevOps Artifacts feed. Run this once:

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

### Interactive Install (Recommended)

```bash
npx @caresolutions/ai-infrastructure init
```

The installer walks you through:
1. **Target directory** — where to install
2. **Components** — checkboxes to pick agents, hooks, commands, MCP servers
3. **Database type** — MongoDB, SQL Server, Azure SQL, PostgreSQL, or None
4. **MCP servers** — Playwright, Teams, Stripe, Azure CLI (pick what you need)
5. **Existing files** — asks to overwrite, skip, or merge each one

### Install to a Specific Project

```bash
npx @caresolutions/ai-infrastructure init /path/to/your/project
```

### Install Everything (No Prompts)

```bash
# Still asks which database type (no sensible default)
npx @caresolutions/ai-infrastructure init --all

# Fully automated — zero prompts
npx @caresolutions/ai-infrastructure init --all --db=mongo
npx @caresolutions/ai-infrastructure init --all --db=mssql
npx @caresolutions/ai-infrastructure init --all --db=azuresql
npx @caresolutions/ai-infrastructure init --all --db=postgres
```

### Install Only Global Agents

Global agents work across all your projects. Install them once:

```bash
npx @caresolutions/ai-infrastructure init --global-only
```

### Re-Running the Installer

Safe to run multiple times. The installer:
- **Skips** files that are identical (no unnecessary changes)
- **Asks** before overwriting files that have changed
- **Merges** MCP server configs (adds missing servers without removing existing ones)

---

## What Gets Installed

```
your-project/
├── .claude/
│   ├── agents/                     # AI sub-agents
│   │   ├── deployer.md             # Commit → push → deploy → monitor
│   │   ├── db-admin.md             # Database queries and data management
│   │   └── devops-tracker.md       # Azure DevOps work item management
│   │
│   ├── hooks/                      # Automated behaviors
│   │   ├── secret-blocker.sh       # BLOCKS hardcoded secrets before write
│   │   ├── protected-files.sh      # BLOCKS/warns on critical file edits
│   │   ├── auto-format.sh          # Auto-runs formatters after edits
│   │   ├── test-on-change.sh       # Suggests related tests after edits
│   │   ├── uat-reminder.sh         # Reminds to run UAT after features
│   │   └── self-improve.sh         # Saves learnings after each session
│   │
│   ├── commands/                   # Slash commands
│   │   ├── implement.md            # /implement AB#1234
│   │   └── review.md              # /review 142
│   │
│   └── settings.json              # Hook and MCP registration
│
├── .mcp.json                      # MCP server configuration
└── CLAUDE.md                      # Gets workflow section appended

~/.claude/agents/                  # Global agents (installed once, all projects)
├── azure-ops.md                   # Azure infrastructure management
├── security-auditor.md            # Security scanning (read-only)
└── api-tester.md                  # API endpoint testing
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
# Updates will install automatically via npx (always fetches latest)
npx @caresolutions/ai-infrastructure init /path/to/project
```

The installer detects existing files and asks whether to overwrite or skip each one.

### Publishing Updates (Maintainers Only)

```bash
cd care-solutions-ai

# Make your changes, then bump the version
npm version patch    # 1.0.0 → 1.0.1
# or
npm version minor    # 1.0.0 → 1.1.0

# Publish to the private feed
npm run publish:feed

# Push to repo
git push && git push --tags
```

---

## Security

- **No secrets in the repo** — `.mcp.json` only contains `${ENV_VAR}` references
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
