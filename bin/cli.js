#!/usr/bin/env node

import { fileURLToPath } from 'url';
import { dirname, join, basename, resolve } from 'path';
import fs from 'fs-extra';
import inquirer from 'inquirer';
import chalk from 'chalk';
import ora from 'ora';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const TEMPLATES_DIR = join(__dirname, '..', 'templates');
const GLOBAL_CLAUDE_DIR = join(process.env.HOME || process.env.USERPROFILE, '.claude');

// ============================================================================
// CLI Arguments
// ============================================================================
const args = process.argv.slice(2);
const showHelp = args.includes('--help') || args.includes('-h');
const globalOnly = args.includes('--global-only');
const installAll = args.includes('--all');
const dbFlag = args.find(a => a.startsWith('--db='))?.split('=')[1] || null;
const targetArg = args.find(a => !a.startsWith('--') && a !== 'init');

if (showHelp) {
  console.log(`
${chalk.blue('Care Solutions AI Infrastructure')}

Usage:
  npx @caresolutions/ai-infrastructure init [target-dir]   Interactive install
  npx @caresolutions/ai-infrastructure init --all          Install everything
  npx @caresolutions/ai-infrastructure init --global-only  Global agents only

Options:
  --all              Install all components (skips identical files, still asks DB type)
  --all --db=mongo   Install all with MongoDB (no prompts at all)
  --all --db=mssql   Install all with SQL Server
  --all --db=azuresql  Install all with Azure SQL
  --all --db=postgres  Install all with PostgreSQL
  --global-only      Only install global agents to ~/.claude/agents/
  --help, -h         Show this help
`);
  process.exit(0);
}

// ============================================================================
// Banner
// ============================================================================
console.log('');
console.log(chalk.blue('╔══════════════════════════════════════════════════╗'));
console.log(chalk.blue('║') + chalk.bold.white('  Care Solutions AI Infrastructure Installer     ') + chalk.blue('║'));
console.log(chalk.blue('╚══════════════════════════════════════════════════╝'));
console.log('');

// ============================================================================
// Helper: install file with overwrite check
// ============================================================================
async function installFile(src, dest, label) {
  if (await fs.pathExists(dest)) {
    const srcContent = await fs.readFile(src, 'utf8');
    const destContent = await fs.readFile(dest, 'utf8');
    if (srcContent === destContent) {
      console.log(chalk.gray(`  = ${label} (identical, skipped)`));
      return false;
    }
    if (installAll) {
      // --all mode: overwrite non-identical files silently
      await fs.ensureDir(dirname(dest));
      await fs.copy(src, dest);
      console.log(chalk.green(`  ✓ ${label} (updated)`));
      return true;
    }
    const { action } = await inquirer.prompt([{
      type: 'list',
      name: 'action',
      message: `${label} already exists:`,
      choices: [
        { name: 'Overwrite', value: 'overwrite' },
        { name: 'Skip', value: 'skip' },
      ],
    }]);
    if (action === 'skip') {
      console.log(chalk.gray(`  ⊘ ${label} (skipped)`));
      return false;
    }
  }
  await fs.ensureDir(dirname(dest));
  await fs.copy(src, dest);
  console.log(chalk.green(`  ✓ ${label}`));
  return true;
}

// ============================================================================
// Step 1: Global Agents (always)
// ============================================================================
async function installGlobalAgents() {
  console.log(chalk.yellow.bold('\n📦 Global Agents → ~/.claude/agents/\n'));

  const globalAgentsDir = join(GLOBAL_CLAUDE_DIR, 'agents');
  await fs.ensureDir(globalAgentsDir);

  const agents = await fs.readdir(join(TEMPLATES_DIR, 'agents', 'global'));
  for (const file of agents) {
    if (file.endsWith('.md')) {
      await installFile(
        join(TEMPLATES_DIR, 'agents', 'global', file),
        join(globalAgentsDir, file),
        file
      );
    }
  }
}

// ============================================================================
// Main Interactive Installer
// ============================================================================
async function main() {
  // Install global agents first
  await installGlobalAgents();

  if (globalOnly) {
    console.log(chalk.green('\n✅ Global agents installed!\n'));
    process.exit(0);
  }

  // ── Target Directory ──────────────────────────────────────────────────
  let targetDir;
  if (targetArg) {
    targetDir = resolve(targetArg);
  } else if (installAll) {
    targetDir = process.cwd();
  } else {
    const { dir } = await inquirer.prompt([{
      type: 'input',
      name: 'dir',
      message: 'Target project directory:',
      default: process.cwd(),
    }]);
    targetDir = resolve(dir);
  }

  if (!await fs.pathExists(targetDir)) {
    console.log(chalk.red(`\n  ✗ Directory does not exist: ${targetDir}\n`));
    process.exit(1);
  }

  console.log(chalk.gray(`\n  Target: ${targetDir}\n`));

  // ── Component Selection ───────────────────────────────────────────────
  let components;
  if (installAll) {
    components = ['agents', 'hooks', 'commands', 'mcp', 'settings', 'workflow', 'gitignore'];
  } else {
    const { selected } = await inquirer.prompt([{
      type: 'checkbox',
      name: 'selected',
      message: 'Select components to install:',
      choices: [
        { name: 'Project Agents (deployer, db-admin, devops-tracker)', value: 'agents', checked: true },
        { name: 'Hooks (secret blocker, auto-format, test suggestions)', value: 'hooks', checked: true },
        { name: 'Slash Commands (11 commands — implement, review, deploy, releases, cherry-pick, promote, rollback, status, cleanup)', value: 'commands', checked: true },
        { name: 'MCP Servers (Playwright, DB, Teams, Stripe, Azure)', value: 'mcp', checked: true },
        { name: 'Settings (hook registration)', value: 'settings', checked: true },
        { name: 'CLAUDE.md Workflow Section', value: 'workflow', checked: true },
        { name: '.gitignore Updates', value: 'gitignore', checked: true },
      ],
    }]);
    components = selected;
  }

  // ── Project Agents ────────────────────────────────────────────────────
  if (components.includes('agents')) {
    console.log(chalk.yellow.bold('\n📦 Project Agents → .claude/agents/\n'));
    const agentsDir = join(targetDir, '.claude', 'agents');
    await fs.ensureDir(agentsDir);
    const agents = await fs.readdir(join(TEMPLATES_DIR, 'agents', 'project'));
    for (const file of agents) {
      if (file.endsWith('.md')) {
        await installFile(
          join(TEMPLATES_DIR, 'agents', 'project', file),
          join(agentsDir, file),
          file
        );
      }
    }
  }

  // ── Hooks ─────────────────────────────────────────────────────────────
  if (components.includes('hooks')) {
    console.log(chalk.yellow.bold('\n🪝 Hooks → .claude/hooks/\n'));
    const hooksDir = join(targetDir, '.claude', 'hooks');
    await fs.ensureDir(hooksDir);
    const hooks = await fs.readdir(join(TEMPLATES_DIR, 'hooks'));
    for (const file of hooks) {
      if (file.endsWith('.sh')) {
        await installFile(
          join(TEMPLATES_DIR, 'hooks', file),
          join(hooksDir, file),
          file
        );
        await fs.chmod(join(hooksDir, file), 0o755);
      }
    }
  }

  // ── Commands ──────────────────────────────────────────────────────────
  if (components.includes('commands')) {
    console.log(chalk.yellow.bold('\n⚡ Slash Commands → .claude/commands/\n'));
    const cmdsDir = join(targetDir, '.claude', 'commands');
    await fs.ensureDir(cmdsDir);
    const cmds = await fs.readdir(join(TEMPLATES_DIR, 'commands'));
    for (const file of cmds) {
      if (file.endsWith('.md')) {
        await installFile(
          join(TEMPLATES_DIR, 'commands', file),
          join(cmdsDir, file),
          file
        );
      }
    }
  }

  // ── MCP Servers (interactive selection) ───────────────────────────────
  let dbType = 'none';
  if (components.includes('mcp')) {
    console.log(chalk.yellow.bold('\n🔌 MCP Servers → .mcp.json\n'));

    let mcpChoices;
    if (installAll) {
      // --all mode: use --db flag or prompt just for database type
      let db = dbFlag;
      if (!db) {
        const { dbAnswer } = await inquirer.prompt([{
          type: 'list',
          name: 'dbAnswer',
          message: 'What database does this project use?',
          choices: [
            { name: 'MongoDB', value: 'mongo' },
            { name: 'SQL Server (local/VM)', value: 'mssql' },
            { name: 'Azure SQL', value: 'azuresql' },
            { name: 'PostgreSQL', value: 'postgres' },
            { name: 'None / Skip', value: 'none' },
          ],
        }]);
        db = dbAnswer;
      }
      mcpChoices = { servers: ['playwright', 'teams', 'azure'], db, stripe: false };
    } else {
      // Database selection
      const { db } = await inquirer.prompt([{
        type: 'list',
        name: 'db',
        message: 'What database does this project use?',
        choices: [
          { name: 'MongoDB', value: 'mongo' },
          { name: 'SQL Server (local/VM)', value: 'mssql' },
          { name: 'Azure SQL', value: 'azuresql' },
          { name: 'PostgreSQL', value: 'postgres' },
          { name: 'None / Skip', value: 'none' },
        ],
      }]);
      dbType = db;

      // Other servers
      const { servers } = await inquirer.prompt([{
        type: 'checkbox',
        name: 'servers',
        message: 'Select additional MCP servers:',
        choices: [
          { name: 'Playwright (browser testing)', value: 'playwright', checked: true },
          { name: 'Microsoft Teams (notifications, messages)', value: 'teams', checked: true },
          { name: 'Stripe (payment management)', value: 'stripe', checked: false },
          { name: 'Azure CLI (App Service, Key Vault, DNS)', value: 'azure', checked: true },
        ],
      }]);

      mcpChoices = { servers, db, stripe: servers.includes('stripe') };
    }

    // Build MCP config
    const mcpConfig = { mcpServers: {} };

    if (mcpChoices.servers.includes('playwright')) {
      mcpConfig.mcpServers.playwright = {
        command: 'npx',
        args: ['@playwright/mcp'],
      };
    }

    if (mcpChoices.db === 'mongo') {
      mcpConfig.mcpServers.mongodb = {
        command: 'npx',
        args: ['-y', 'mongodb-mcp-server'],
        env: { MDB_MCP_CONNECTION_STRING: '${MONGODB_CONNECTION_STRING}' },
      };
    } else if (mcpChoices.db === 'mssql' || mcpChoices.db === 'azuresql') {
      mcpConfig.mcpServers.mssql = {
        command: 'npx',
        args: ['-y', '@anthropic/mcp-mssql-server'],
        env: { MSSQL_CONNECTION_STRING: '${MSSQL_CONNECTION_STRING}' },
      };
    } else if (mcpChoices.db === 'postgres') {
      mcpConfig.mcpServers.postgres = {
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-postgres'],
        env: { POSTGRES_CONNECTION_STRING: '${POSTGRES_CONNECTION_STRING}' },
      };
    }

    if (mcpChoices.servers.includes('teams')) {
      mcpConfig.mcpServers.teams = {
        command: 'npx',
        args: ['-y', '@anthropic/mcp-teams-server'],
        env: {
          TEAMS_TENANT_ID: '${TEAMS_TENANT_ID}',
          TEAMS_CLIENT_ID: '${TEAMS_CLIENT_ID}',
          TEAMS_CLIENT_SECRET: '${TEAMS_CLIENT_SECRET}',
        },
      };
    }

    if (mcpChoices.servers.includes('stripe') || mcpChoices.stripe) {
      mcpConfig.mcpServers.stripe = {
        command: 'npx',
        args: ['-y', '@stripe/mcp'],
        env: { STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}' },
      };
    }

    if (mcpChoices.servers.includes('azure')) {
      mcpConfig.mcpServers.azure = {
        command: 'npx',
        args: ['-y', '@azure/mcp@latest', 'server', 'start'],
      };
    }

    dbType = mcpChoices.db;

    const mcpPath = join(targetDir, '.mcp.json');
    if (await fs.pathExists(mcpPath)) {
      // In --all mode, check if content is identical first
      const newContent = JSON.stringify(mcpConfig, null, 2);
      const existingContent = await fs.readFile(mcpPath, 'utf8');
      if (newContent.trim() === existingContent.trim()) {
        console.log(chalk.gray('  = .mcp.json (identical, skipped)'));
      } else {
      const { action } = installAll
        ? { action: 'overwrite' }
        : await inquirer.prompt([{
            type: 'list',
            name: 'action',
            message: '.mcp.json already exists:',
            choices: [
              { name: 'Overwrite with new config', value: 'overwrite' },
              { name: 'Merge (add missing servers)', value: 'merge' },
              { name: 'Skip', value: 'skip' },
            ],
          }]);

      if (action === 'merge') {
        const existing = await fs.readJson(mcpPath);
        existing.mcpServers = { ...existing.mcpServers, ...mcpConfig.mcpServers };
        await fs.writeJson(mcpPath, existing, { spaces: 2 });
        console.log(chalk.green('  ✓ .mcp.json (merged)'));
      } else if (action === 'overwrite') {
        await fs.writeJson(mcpPath, mcpConfig, { spaces: 2 });
        console.log(chalk.green('  ✓ .mcp.json (overwritten)'));
      } else {
        console.log(chalk.gray('  ⊘ .mcp.json (skipped)'));
      }
      } // close identical check else
    } else {
      await fs.writeJson(mcpPath, mcpConfig, { spaces: 2 });
      console.log(chalk.green('  ✓ .mcp.json'));
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────
  if (components.includes('settings')) {
    console.log(chalk.yellow.bold('\n⚙️  Settings → .claude/settings.json\n'));
    await installFile(
      join(TEMPLATES_DIR, 'infrastructure', 'settings.json'),
      join(targetDir, '.claude', 'settings.json'),
      'settings.json'
    );
  }

  // ── CLAUDE.md Workflow ────────────────────────────────────────────────
  if (components.includes('workflow')) {
    console.log(chalk.yellow.bold('\n📄 CLAUDE.md Workflow\n'));
    const claudeMdPath = join(targetDir, 'CLAUDE.md');
    const workflowContent = await fs.readFile(
      join(TEMPLATES_DIR, 'infrastructure', 'CLAUDE-WORKFLOW.md'),
      'utf8'
    );

    const sensitiveDataPolicy = `## SENSITIVE DATA — MANDATORY RULE

**NEVER query, display, read, grep, or expose sensitive PII fields from the database or codebase — even if the values are encrypted.** Blocked fields: TIN, SSN, EIN, TaxId, BankAccountNumber, RoutingNumber, and any \`Encrypted*\` variants. Always use explicit inclusion projections listing only non-sensitive fields. Direct users to the application UI for sensitive data access.
`;

    if (!await fs.pathExists(claudeMdPath)) {
      await fs.writeFile(claudeMdPath, `# ${basename(targetDir)}\n\n${sensitiveDataPolicy}\n${workflowContent}`);
      console.log(chalk.green('  ✓ Created CLAUDE.md with sensitive data policy and workflow'));
    } else {
      let existing = await fs.readFile(claudeMdPath, 'utf8');

      // Inject sensitive data policy if not present
      if (!existing.includes('SENSITIVE DATA — MANDATORY RULE')) {
        // Insert after the first heading line, or at the top
        const firstHeadingEnd = existing.indexOf('\n');
        if (firstHeadingEnd !== -1 && existing.startsWith('#')) {
          existing = existing.slice(0, firstHeadingEnd + 1) + '\n' + sensitiveDataPolicy + existing.slice(firstHeadingEnd + 1);
        } else {
          existing = sensitiveDataPolicy + '\n' + existing;
        }
        await fs.writeFile(claudeMdPath, existing);
        console.log(chalk.green('  ✓ Injected sensitive data policy into CLAUDE.md'));
      } else {
        console.log(chalk.gray('  = Sensitive data policy already exists'));
      }

      // Re-read in case we just modified it
      existing = await fs.readFile(claudeMdPath, 'utf8');

      if (existing.includes('Care Solutions AI Workflow')) {
        console.log(chalk.gray('  = Workflow section already exists'));
        if (!installAll) {
          const { replace } = await inquirer.prompt([{
            type: 'confirm',
            name: 'replace',
            message: 'Replace existing workflow section?',
            default: false,
          }]);
          if (replace) {
            const cleaned = existing.replace(/\n## Care Solutions AI Workflow[\s\S]*$/, '').trimEnd();
            await fs.writeFile(claudeMdPath, `${cleaned}\n\n${workflowContent}`);
            console.log(chalk.green('  ✓ Workflow section replaced'));
          }
        }
      } else {
        await fs.appendFile(claudeMdPath, `\n\n${workflowContent}`);
        console.log(chalk.green('  ✓ Workflow appended to CLAUDE.md'));
      }
    }
  }

  // ── .gitignore ────────────────────────────────────────────────────────
  if (components.includes('gitignore')) {
    console.log(chalk.yellow.bold('\n🙈 .gitignore\n'));
    const gitignorePath = join(targetDir, '.gitignore');
    const claudeBlock = `
# =========================
# Claude Code
# =========================
.claude/*
!.claude/agents/
!.claude/hooks/
!.claude/commands/
!.claude/settings.json
.claude/settings.local.json`;

    if (await fs.pathExists(gitignorePath)) {
      const content = await fs.readFile(gitignorePath, 'utf8');
      if (content.includes('.claude/*')) {
        console.log(chalk.gray('  = Claude entries already exist'));
      } else {
        await fs.appendFile(gitignorePath, claudeBlock);
        console.log(chalk.green('  ✓ Added Claude entries'));
      }
    } else {
      await fs.writeFile(gitignorePath, claudeBlock.trim());
      console.log(chalk.green('  ✓ Created .gitignore'));
    }
  }

  // ── Summary ───────────────────────────────────────────────────────────
  const agentCount = (await fs.pathExists(join(targetDir, '.claude', 'agents')))
    ? (await fs.readdir(join(targetDir, '.claude', 'agents'))).filter(f => f.endsWith('.md')).length
    : 0;
  const hookCount = (await fs.pathExists(join(targetDir, '.claude', 'hooks')))
    ? (await fs.readdir(join(targetDir, '.claude', 'hooks'))).filter(f => f.endsWith('.sh')).length
    : 0;
  const cmdCount = (await fs.pathExists(join(targetDir, '.claude', 'commands')))
    ? (await fs.readdir(join(targetDir, '.claude', 'commands'))).filter(f => f.endsWith('.md')).length
    : 0;
  const globalCount = (await fs.pathExists(join(GLOBAL_CLAUDE_DIR, 'agents')))
    ? (await fs.readdir(join(GLOBAL_CLAUDE_DIR, 'agents'))).filter(f => f.endsWith('.md')).length
    : 0;

  console.log('');
  console.log(chalk.blue('╔══════════════════════════════════════════════════╗'));
  console.log(chalk.blue('║') + chalk.green.bold('  ✅ Installation Complete!                       ') + chalk.blue('║'));
  console.log(chalk.blue('╚══════════════════════════════════════════════════╝'));
  console.log('');
  console.log(`  Target:          ${chalk.bold(targetDir)}`);
  console.log(`  Project agents:  ${chalk.bold(agentCount)}`);
  console.log(`  Hooks:           ${chalk.bold(hookCount)}`);
  console.log(`  Commands:        ${chalk.bold(cmdCount)}`);
  console.log(`  Global agents:   ${chalk.bold(globalCount)}`);
  console.log(`  Database:        ${chalk.bold(dbType)}`);
  console.log('');

  // Show required env vars
  console.log(chalk.yellow('  Environment variables to set:'));
  if (dbType === 'mongo') console.log(chalk.gray('    export MONGODB_CONNECTION_STRING="mongodb+srv://..."'));
  if (dbType === 'mssql' || dbType === 'azuresql') console.log(chalk.gray('    export MSSQL_CONNECTION_STRING="Server=...;Database=..."'));
  if (dbType === 'postgres') console.log(chalk.gray('    export POSTGRES_CONNECTION_STRING="postgresql://..."'));
  console.log(chalk.gray('    export TEAMS_TENANT_ID="..." TEAMS_CLIENT_ID="..." TEAMS_CLIENT_SECRET="..."'));
  console.log(chalk.gray('    az login'));
  console.log('');
  console.log(`  Then: ${chalk.blue(`cd ${targetDir} && claude`)}`);
  console.log(`  Run:  ${chalk.blue('/implement AB#1234')} to start working`);
  console.log(`  Run:  ${chalk.blue('/review 142')} to review a PR`);
  console.log('');
}

main().catch(err => {
  console.error(chalk.red(`\n  Error: ${err.message}\n`));
  process.exit(1);
});
