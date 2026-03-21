# Care Solutions AI Infrastructure

> Personal AI Infrastructure for [Claude Code](https://claude.ai/code) — an internal package that gives every Care Solutions team member a standardized, AI-powered development experience.

**Private package.** Restricted to Care Solutions Azure DevOps organization members.

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

## Installation

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- [Node.js](https://nodejs.org/) 18 or later
- Git access to this repo

### Quick Start

```bash
# 1. Clone this repo
git clone https://dev.azure.com/caresolutionsinc/Care%20Solutions%20AI/_git/Care%20Solutions%20AI
cd "Care Solutions AI"

# 2. Install dependencies
npm install

# 3. Run the interactive installer on your project
node bin/cli.js init /path/to/your/project
```

### Install Options

```bash
# Interactive mode (recommended) — choose what you need
node bin/cli.js init /path/to/project

# Install everything without prompts
node bin/cli.js init /path/to/project --all

# Install only global agents (works across all projects)
node bin/cli.js init --global-only

# Show help
node bin/cli.js --help
```

### What the Installer Asks

The interactive installer walks you through:

1. **Target directory** — where to install
2. **Component selection** — checkboxes to pick agents, hooks, commands, MCP servers, etc.
3. **Database type** — MongoDB, SQL Server, Azure SQL, PostgreSQL, or None
4. **MCP servers** — pick which integrations you need:
   - Playwright (browser testing)
   - Microsoft Teams (notifications)
   - Stripe (payment management)
   - Azure CLI (infrastructure)
5. **Existing files** — overwrite, skip, or merge for each file that already exists

### What Gets Installed

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

### The Development Workflow

**Implementing a work item:**

```
1. Open your project:     cd /path/to/project && claude
2. Verify MCP:            /mcp
3. Start work:            /implement AB#1234
```

Claude automatically:
- Reads the work item from Azure DevOps
- Explores the codebase and plans the approach
- Delegates to backend/frontend agents to implement
- Runs tests, linting, and build validation
- Generates a UAT checklist from acceptance criteria
- **Pauses for you to manually test**
- Creates the PR after you confirm

**Reviewing a pull request:**

```
/review 142
```

Claude automatically:
- Reads the full PR diff
- Reads the linked work item and checks all acceptance criteria
- Reviews for Clean Architecture, security, missing tests, code quality
- Posts inline comments on all findings
- Posts a PR-level summary
- Asks: "Approve, Request Changes, or skip the vote?"

### Hooks in Action

These run automatically — no action needed:

| When | What Happens | Why |
|------|-------------|-----|
| Before any file write | Secret blocker scans for credentials | Prevents leaking API keys, connection strings, passwords |
| Before any file edit | Protected files guard checks the path | Prevents accidental edits to production configs |
| After any file edit | Auto-formatter runs | Keeps code style consistent (dotnet format / eslint) |
| After any file edit | Test suggestion appears | Reminds you which tests to run |
| When Claude stops | UAT reminder | Don't forget to test before marking done |
| When Claude stops | Self-improvement prompt | Claude saves what it learned for next time |

---

## Environment Setup

Each team member sets their own environment variables. **Never commit these.**

```bash
# Add to ~/.zshrc (Mac) or System Environment Variables (Windows)

# MongoDB (if your project uses MongoDB)
export MONGODB_CONNECTION_STRING="mongodb+srv://user:password@cluster.mongodb.net/"

# SQL Server (if your project uses SQL Server)
export MSSQL_CONNECTION_STRING="Server=localhost;Database=MyDb;User Id=sa;Password=...;"

# Microsoft Teams (for team notifications)
export TEAMS_TENANT_ID="your-azure-ad-tenant-id"
export TEAMS_CLIENT_ID="your-app-registration-client-id"
export TEAMS_CLIENT_SECRET="your-client-secret"

# Stripe (if your project uses Stripe)
export STRIPE_SECRET_KEY="sk_test_..."

# Azure CLI (no env var needed — just log in)
az login
```

### Setting Up Teams MCP Server

1. Go to [Azure Portal > App Registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps)
2. New Registration → name it "Claude Code Teams Bot"
3. API Permissions → add Microsoft Graph: `ChannelMessage.Send`, `Chat.ReadWrite`, `Team.ReadBasic.All`
4. Create a client secret
5. Set the three TEAMS env vars above

---

## Customization

### Adding Custom Agents

Create `.claude/agents/your-agent.md` in your project:

```markdown
---
name: your-agent
description: What this agent does — shown in agent selection
tools:
  - Bash
  - Read
  - Write
---

# Your Agent Name

Instructions for what this agent does and how it behaves...
```

### Adding Custom Hooks

1. Create `.claude/hooks/your-hook.sh` — make it executable
2. Add it to `.claude/settings.json` under the appropriate event (PreToolUse, PostToolUse, or Stop)

### Adding Custom Slash Commands

Create `.claude/commands/your-command.md`:

```markdown
Do something with $ARGUMENTS.

1. Step one
2. Step two
3. Step three
```

Then use it: `/your-command some-argument`

### Removing Components

Delete any agent, hook, command, or MCP server you don't need. Everything works independently.

---

## Security

- **No secrets in the repo** — `.mcp.json` only contains `${ENV_VAR}` references
- **Secret blocker hook** — automatically blocks writes containing hardcoded credentials
- **Protected files hook** — prevents edits to production configs
- **`.claude/settings.local.json`** is gitignored — personal permissions stay private
- **Private repo** — only Care Solutions Azure DevOps org members have access

---

## Updating

When the infrastructure is updated:

```bash
cd "Care Solutions AI"
git pull
node bin/cli.js init /path/to/project
```

The installer detects existing files and asks whether to overwrite, skip, or merge each one.

---

## Support

- **Issues:** Contact the engineering team via Teams
- **Documentation:** This README + CLAUDE.md workflow section in each project
- **Source:** https://dev.azure.com/caresolutionsinc/Care%20Solutions%20AI

## License

MIT — Care Solutions internal use.
