# Care Solutions AI Infrastructure

A portable Personal AI Infrastructure for [Claude Code](https://claude.ai/code) — agents, hooks, MCP servers, slash commands, and an automated development workflow.

**Private package.** Restricted to Care Solutions team via Azure DevOps Artifacts.

## Quick Install

```bash
npx @caresolutions/ai-infrastructure init
```

Or install into a specific project:
```bash
npx @caresolutions/ai-infrastructure init /path/to/project
```

Install everything without prompts:
```bash
npx @caresolutions/ai-infrastructure init --all
```

Global agents only:
```bash
npx @caresolutions/ai-infrastructure init --global-only
```

## What You Get

- **3 project agents** — deployer, db-admin, devops-tracker
- **3 global agents** — azure-ops, security-auditor, api-tester
- **6 hooks** — secret blocker, protected files, auto-format, test suggestions, UAT reminder, self-improve
- **2 slash commands** — `/implement AB#1234`, `/review 142`
- **6 MCP servers** — Playwright, MongoDB/SQL/Postgres, Teams, Stripe, Azure
- **CLAUDE.md workflow** — end-to-end development process

## Workflow

```
/implement AB#1234  →  auto-delegates to agents  →  tests pass  →  you manually test  →  PR created
/review 142         →  reads diff + work item  →  posts comments  →  asks for your vote
```

## Setup

Each team member sets their own env vars (never committed):

```bash
export MONGODB_CONNECTION_STRING="mongodb+srv://..."
export TEAMS_TENANT_ID="..." 
export TEAMS_CLIENT_ID="..."
export TEAMS_CLIENT_SECRET="..."
export STRIPE_SECRET_KEY="sk_test_..."
az login
```

## License

MIT — Care Solutions internal use.
