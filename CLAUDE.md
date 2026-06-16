# Claude Kit — Repo Instructions

## SENSITIVE DATA — MANDATORY RULE

**NEVER query, display, read, grep, or expose sensitive PII fields from the database or codebase — even if the values are encrypted.** Blocked fields: TIN, SSN, EIN, TaxId, BankAccountNumber, RoutingNumber, and any `Encrypted*` variants. Always use explicit inclusion projections listing only non-sensitive fields. Direct users to the application UI for sensitive data access.

This repo IS the package — it is not a project that consumes Claude Kit. When working here, you are editing the installer itself, not a project that the installer ran against.

## What this repo is

`@chris1807/claude-kit` is an npm CLI that installs Claude Code infrastructure (agents, hooks, MCP servers, slash commands, workflow) into a target project:

```bash
npx @chris1807/claude-kit init [target-dir]
```

The CLI lives in `bin/cli.js`. The content it copies into target projects lives in `templates/`.

## Layout

- `bin/cli.js` — the installer (Node ESM, single file). Reads from `templates/`, writes to the target project's `.claude/` and to `~/.claude/agents/` for global agents.
- `templates/agents/global/` — agent .md files copied to `~/.claude/agents/`. Available in every project on the user's machine.
- `templates/agents/project/` — agent .md files copied to `<target>/.claude/agents/`. Project-scoped.
- `templates/hooks/` — shell hook scripts copied to `<target>/.claude/hooks/` (mode 0755).
- `templates/commands/` — slash command .md files copied to `<target>/.claude/commands/`.
- `templates/infrastructure/` — `settings.json`, `mcp.json`, `CLAUDE-WORKFLOW.md`, `azure-pipelines-template.yml`. Used to seed project-level config.
- `docs/` — author-facing documentation (not shipped, not installed; just for the repo).
- `.github/workflows/publish.yml` — auto-publishes to npm when a `v*` tag is pushed.

## Two kinds of edit, very different effects

**Edits to `bin/cli.js` or `package.json`** change installer behavior. Bump the version and publish to ship them.

**Edits to anything under `templates/`** change what gets installed into target projects. Bump the package version so the auto-update path (see below) picks it up.

### Auto-update on session start

Installed projects get a `SessionStart` hook (`.claude/hooks/kit-update-check.sh`) that:

1. Reads `.claude/.kit-install.json` for the installed version and saved choices (db, adoOrg).
2. Queries npm for the latest published `@chris1807/claude-kit` version (5s timeout, silent on failure).
3. If newer, re-runs `npx @chris1807/claude-kit init --all --db=<saved> [--ado-org=<saved>]` against the project root.
4. Throttled to once per 24h via `.claude/.kit-update-check`.

This means **template changes reach users automatically** the next time they open a session, up to a day after the new version is published. They do not have to re-run the installer manually.

User-customized files are protected by the merge logic in `bin/cli.js`:
- `.claude/settings.json` — additive merge: kit hooks are added if missing, user-added hooks are never removed, top-level keys the user changed are never overwritten.
- `.mcp.json` — merge by default in `--all`: missing servers are added, user-added servers are preserved.
- `CLAUDE.md` workflow section — replaced only when it differs from the current template.

## Local testing

Before publishing:

```bash
npm link                                # symlinks claude-kit globally
mkdir /tmp/kit-test && cd /tmp/kit-test
claude-kit --help                       # banner shows "Claude Kit"
claude-kit init --global-only           # writes ~/.claude/agents/* (idempotent — safe to run)
claude-kit init . --all --db=mongo      # full install into /tmp/kit-test
```

To unlink: `npm unlink -g @chris1807/claude-kit`.

### Non-interactive contexts

The installer detects non-TTY stdin (CI runs, piped invocations, agent shells) at startup and exits with a clear error rather than hanging on a prompt. To run cleanly in those contexts, use either `--global-only` or `--all --db=<...>` (optionally with `--ado-org=<name>`). Plain `init` and `--all` without `--db=` both require a TTY.

Inspect what `npm publish` would ship without actually publishing:

```bash
npm pack --dry-run
npm publish --dry-run --access public
```

## Publishing

Do **not** run `npm publish` from a dev machine. The GitHub Action at `.github/workflows/publish.yml` is the only publishing path, so every published version is traceable to a tagged commit.

```bash
npm version patch     # bumps package.json + creates a v* git tag
git push && git push --tags
```

The action verifies the tag name matches `package.json` `version`, then runs `npm publish --provenance --access public` using the `NPM_TOKEN` repo secret.

If publish fails, inspect the action log on GitHub. Do not retry by publishing locally — fix the issue, bump the version again, push a new tag.

## Branch convention

Solo project — work on `main`. No PR gate. Commits land directly.

## Files to never commit

`.gitignore` already covers `node_modules/`, `.env`, `_password`. Don't add npm tokens, PATs, or other secrets to the repo. The `NPM_TOKEN` secret lives in GitHub Actions secrets, not in any file.

## Agent model selection

Every agent .md under `templates/agents/` sets `model:` in its frontmatter. Three valid forms, picked deliberately:

1. **`inherit`** — the agent uses whatever frontier model the user's session is on. Use this for agents that should match user intent (the user picked Opus for a reason — that reason applies to the manager and to the implementers too). Currently: `manager`, `backend`, `frontend`, `mockup`.
2. **Tier alias** (`opus`, `sonnet`, `haiku`) — the agent always runs at a specific tier regardless of session model. Use this when the task has a known cost/capability target that's independent of what the user picked. Aliases auto-resolve to the latest model in that tier, so they don't rot.
   - `sonnet` — specialized agents whose work doesn't need frontier reasoning: `api-tester`, `azure-ops`, `legacy`, `reviewer`, `security-auditor`, `test-runner`, `uat-generator`.
   - `haiku` — cheap mechanical agents: `build-validator`, `lint-checker`.
3. **Pinned model ID** (e.g. `claude-opus-4-7`) — DO NOT USE unless you have a hard reason. Pinned IDs rot the moment a new model ships, and a typo'd ID silently breaks the agent at runtime (the harness accepts any string). The kit briefly pinned `claude-opus-4-8` (didn't exist) in 2.1.13 and had to roll back in 2.1.14 — this is the exact failure mode to avoid.

**Default decision tree:** Does the agent need to match the user's chosen capability level? → `inherit`. Is it a known-cheap mechanical job? → `haiku`. Otherwise → `sonnet`. Reach for a pinned ID only if you've manually verified the ID exists and have a reason aliases won't work.

## When editing template content

Template files contain placeholders like `{{DEV_WEBSITE_NAME}}` (in `azure-pipelines-template.yml`) and Care Solutions example domains (`*.caresolutions.com`) that are intentionally illustrative. Don't strip placeholder syntax — `bin/cli.js` doesn't currently substitute these, so users edit them by hand after install. If you want to add substitution, that's an installer feature, not a template change.

The phrase "Claude Kit Workflow" is a marker `bin/cli.js` looks for in target `CLAUDE.md` files to detect re-installs (see `cli.js` around line 426). Don't rename it without updating the detection logic. The old marker "Care Solutions AI Workflow" is also matched as a fallback so v1 installs can still be re-run cleanly.
