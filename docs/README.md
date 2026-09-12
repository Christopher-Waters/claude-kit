# Claude Kit Documentation

> Claude Kit is a Claude Code starter kit built around **Azure DevOps**. Every workflow below assumes work items live in Azure DevOps, code lives in Azure Repos, and CD runs on Azure Pipelines. The Azure DevOps MCP server is the backbone — slash commands are thin wrappers over its APIs.

## Guides

- [Slash Commands Guide](slash-commands-guide.md) — Real-world examples for all commands: /implement, /review, /resolve-feedback, /rework, /deploy, /create-release, /deploy-release, /add-to-release, /cherry-pick, /promote, /rollback, /track, /cleanup-branches, /close-orphan-tasks
- [Agent Authoring Notes](agent-authoring.md) — model selection, tool allowlists (including why the `qa` agent's security model is what it omits), and the house shape for an agent file
- [Pipeline & Branching Migration Guide](pipeline-migration-guide.md) — Current state of Azure Pipelines across projects, target branching strategy, and migration steps for COMPASS, CSIPay, and Glasswing
- [Roadmap — Autonomous Delivery Pipeline](roadmap-autonomous-pipeline.md) — **not scheduled.** Captured design for a serial `/implement-sprint`, an autonomous devops agent, and a recording qa agent, with the work item state as the queue
- [Pipeline Migration TODO](todo-pipeline-migration.md) — Checklist for migrating COMPASS, Glasswing, and CSIPay to the standard Azure DevOps branching and pipeline setup
