# Agent Authoring Notes

Conventions for the agent `.md` files under `templates/agents/`. These live here rather than in the repo's `CLAUDE.md` because that file is gitignored — this is the tracked copy.

## Model selection

Every agent sets `model:` in its frontmatter. Three valid forms, picked deliberately:

1. **`inherit`** — the agent uses whatever frontier model the session is on. For agents whose quality should track user intent: the user picked Opus for a reason, and that reason applies to the implementers too. Currently `backend`, `frontend`, `mockup`.
2. **Tier alias** (`opus`, `sonnet`, `haiku`) — a fixed tier regardless of session model, for work with a known cost/capability target. Aliases auto-resolve to the latest model in the tier, so they don't rot.
   - `sonnet` — specialized agents that don't need frontier reasoning: `azure-ops`, `legacy`, `qa`, `reviewer`, `security-auditor`, `test-runner`.
   - `haiku` — cheap mechanical agents: `build-validator`, `lint-checker`.
3. **Pinned model ID** — **don't.** Pinned IDs rot the moment a new model ships, and a typo'd ID silently breaks the agent at runtime because the harness accepts any string. The kit briefly pinned `claude-opus-4-8` (which didn't exist) in 2.1.13 and rolled back in 2.1.14.

**Decision tree:** must it match the user's chosen capability level? → `inherit`. Known-cheap mechanical job? → `haiku`. Otherwise → `sonnet`.

## Tool allowlists

`tools:` is an **allowlist that replaces inheritance** — an agent listing any tool gets only what it lists. MCP tools must be named individually (`mcp__playwright__browser_click`); naming a server does nothing.

`templates/agents/global/qa.md` is the first agent in the kit to declare `mcp__*` tools, and its security model is **what it omits**:

| Withheld | Why |
|---|---|
| `browser_evaluate`, `browser_run_code_unsafe` | Arbitrary page JS could read any DOM value and defeat every sensitive-data rule in the file. |
| `browser_network_request` (singular) | Returns full request and response bodies — the likeliest route for a TIN or SSN into a transcript. Only the plural `browser_network_requests` (method/URL/status) is granted. |
| `browser_file_upload`, `browser_drag`, `browser_drop` | Not needed by the current checklist. Add narrowly if a story requires them. |
| every `mcp__azure-devops__*` tool | The agent must be structurally unable to advance a work item. That is what makes "`/qa` never changes state" a guarantee instead of a promise. |

**Omission is the enforcement.** The same restriction written as prose in the agent body is only a suggestion the model can talk itself out of. So:

- Never widen a browser agent's tool list without re-reading its sensitive-data rules.
- Verify every `mcp__*` name against the running server before shipping — the harness accepts any string, and a typo means the agent silently lacks the tool.
- Re-check the allowlist when bumping `@playwright/mcp`. A renamed tool disappears silently, which is why `qa.md` is instructed to report a missing capability rather than improvise around it.

## File shape

`---` frontmatter (`name`, `description`, `tools`, optional `disallowedTools`, `model`) → one `# Title Case Name` → a one- or two-sentence "You …" identity paragraph → `## Project Discovery` for anything that runs inside a user repo (discover with `Glob`, always read the project's `CLAUDE.md`, never hardcode paths) → domain sections → an optional `## Report Format` holding the verbatim output template → a closing `## Rules` list. Bodies run 50–255 lines; 60–130 is typical.

Adding a file to `templates/agents/global/` or `templates/agents/project/` is all that's required to ship it — `bin/cli.js` globs those directories. The only hardcoded filename lists are `RETIRED_GLOBAL_AGENTS` and `RETIRED_PROJECT_AGENTS`, which delete files from prior versions; a new agent's name must not collide with those.
