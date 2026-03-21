
## Care Solutions AI Workflow

This project uses the Care Solutions Personal AI Infrastructure — a standardized set of agents, hooks, MCP servers, and workflows shared across all Care Solutions projects.

### Agent Pipeline

When given a task, Claude Code can delegate through specialized agents:

```
You (give task)
  ├── Explore → finds relevant files
  ├── Plan → designs the approach
  ├── backend / frontend → implements code
  ├── deployer → commits, pushes, triggers CD pipeline
  ├── db-admin → queries/fixes MongoDB data
  ├── devops-tracker → creates/updates Azure DevOps work items
  ├── test-runner → runs xUnit, Vitest, Playwright tests
  ├── build-validator → confirms builds pass
  ├── lint-checker → runs ESLint and dotnet format
  ├── security-auditor → scans for secrets, vulnerabilities
  ├── api-tester → tests API endpoints with curl
  ├── azure-ops → manages Azure infrastructure
  └── reviewer → reviews code quality
```

### Sensitive Data Policy

**NEVER query, display, or expose sensitive PII fields from the database — even if the values are encrypted.** This includes TIN, SSN, EIN, TaxId, BankAccountNumber, RoutingNumber, and any `Encrypted*` variants. Even encrypted/hashed values must not appear in output, logs, or summaries. When querying collections that may contain sensitive fields, always use explicit inclusion projections listing only the non-sensitive fields needed. If a user requests access to sensitive data, direct them to use the application UI.

### Automated Hooks

These run automatically — no action needed:

| When | What Happens |
|------|-------------|
| **Before any Bash command** | Sensitive data blocker prevents database queries that reference TIN, SSN, or other PII fields |
| **Before any file write** | Secret blocker scans for hardcoded credentials and blocks them |
| **Before any file edit** | Protected files guard warns/blocks edits to production configs |
| **After any file edit** | Auto-formatter runs (dotnet format for .cs, eslint --fix for .ts) |
| **After any file edit** | Test suggestions appear for related test files |
| **When Claude stops** | UAT reminder if a feature was implemented |
| **When Claude stops** | Self-improvement prompt to save learnings to memory |

### MCP Servers Available

| Server | What It Does |
|--------|-------------|
| **Azure DevOps** | Work items, pipelines, repos, wiki |
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
2. **Claude implements** using the appropriate agents
3. **Hooks guard** against secrets and bad patterns automatically
4. **Deploy** using the deployer agent (commit → push → pipeline → verify)
5. **Test** using Playwright MCP for browser testing
6. **Track** work items using the devops-tracker agent
7. **Learn** — Claude saves what worked for next time

### Environment Setup

Each team member needs to set their own environment variables (never commit these):

```bash
# MongoDB (required for db-admin agent)
export MONGODB_CONNECTION_STRING="mongodb+srv://..."

# Microsoft Teams (required for team notifications)
export TEAMS_TENANT_ID="..."
export TEAMS_CLIENT_ID="..."
export TEAMS_CLIENT_SECRET="..."

# Stripe (required when payment integration is active)
export STRIPE_SECRET_KEY="sk_test_..."

# Azure (use az login instead of env vars)
az login
```
