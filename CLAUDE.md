# Claude Kit — Repo Instructions

This repo IS the package — it is not a project that consumes Claude Kit. When working here, you are editing the installer itself, not a project that the installer ran against.

## What this repo is

`@chriswaters/claude-kit` is an npm CLI that installs Claude Code infrastructure (agents, hooks, MCP servers, slash commands, workflow) into a target project:

```bash
npx @chriswaters/claude-kit init [target-dir]
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

**Edits to anything under `templates/`** change what gets installed into target projects. Existing installs do NOT auto-update; users re-run `npx @chriswaters/claude-kit init` (or `--all`) to pick up template changes. Bump the version anyway so users can see new content is available.

## Local testing

Before publishing:

```bash
npm link                                # symlinks claude-kit globally
mkdir /tmp/kit-test && cd /tmp/kit-test
claude-kit --help                       # banner shows "Claude Kit"
claude-kit init --global-only           # writes ~/.claude/agents/* (idempotent — safe to run)
claude-kit init . --all --db=mongo      # full install into /tmp/kit-test
```

To unlink: `npm unlink -g @chriswaters/claude-kit`.

Inspect what `npm publish` would ship without actually publishing:

```bash
npm pack --dry-run
npm publish --dry-run --access public
```

## Publishing

Do **not** run `npm publish` from a dev machine. The GitHub Action at `.github/workflows/publish.yml` is the only publishing path, so every published version is traceable to a tagged commit and carries npm provenance.

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

## When editing template content

Template files contain placeholders like `{{DEV_WEBSITE_NAME}}` (in `azure-pipelines-template.yml`) and Care Solutions example domains (`*.caresolutions.com`) that are intentionally illustrative. Don't strip placeholder syntax — `bin/cli.js` doesn't currently substitute these, so users edit them by hand after install. If you want to add substitution, that's an installer feature, not a template change.

The phrase "Claude Kit Workflow" is a marker `bin/cli.js` looks for in target `CLAUDE.md` files to detect re-installs (see `cli.js` around line 426). Don't rename it without updating the detection logic. The old marker "Care Solutions AI Workflow" is also matched as a fallback so v1 installs can still be re-run cleanly.
