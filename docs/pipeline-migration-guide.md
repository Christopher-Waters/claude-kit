# Pipeline & Branching Migration Guide

> This document covers the current state of pipelines and branching across your projects, the target state, and the migration steps for each project.

> **Status 2026-09-06.** The target changed from the original 3-branch plan (`develop`/`staging`/`main`) to the 5-branch layout below, in which `main` is a pure compare branch and each environment has its own lowercase branch. **COMPASS and CSIPay are on the new layout** (CSIPay renamed its branches on 2026-09-04; `test` replaced `QA`). **Glasswing and Monarch is not yet migrated** — it still has only `main` and `develop`. The phase-by-phase steps further down were written against the old plan; read them with the table below in mind (`develop` → `dev`, production is `prod`, and `main` never deploys). See `docs/todo-pipeline-migration.md` for what's verified done.

---

## Target State (All Projects)

### Branch-to-Environment Mapping

`main` is the **compare branch** — the default branch, the one feature PRs target, and the one every environment is compared against. **Merging a PR into `main` deploys nothing.** Each environment has its own branch, and a PR merging into that branch is what triggers its CD pipeline:

| Branch | Environment | Deploys When |
|--------|-------------|-------------|
| `main` | — (compare / integration) | **Never** |
| `dev` | Development | PR merged into `dev` |
| `test` | Test (QA) | PR merged into `test` |
| `staging` | Staging | PR merged into `staging` |
| `prod` | Production | PR merged into `prod` |

Work item states mirror the chain: `Code Review` (PR open to `main`) → `Ready for Testing` (on `dev`) → `Testing` (on `test`) → `Ready for Staging` (QA sign-off) → `Staging` (on `staging`) → `Ready to Deploy` (stakeholder sign-off) → `Deployed` (on `prod`) → `Closed`. `Ready for Staging` and `Staging` were added to the CSI Development process on 2026-09-06. The promotion slash commands gate-check against the "Ready for …" states and advance items after the merge.

### Pipeline Standard

All projects should use **YAML multi-stage pipelines** (not classic Build + Release):
- Single YAML file per app (API, Client, etc.)
- Triggers from all environment branches
- Branch-conditional stages deploy to the correct environment
- Defined in the repo as code — versioned, reviewable, portable

### Branch Naming Convention

Feature branches created by `/implement` follow this convention:

| Work Item Type | Branch Prefix | Example |
|----------------|--------------|---------|
| Feature | `feature/` | `feature/AB#1234-add-payment-export` |
| User Story | `story/` | `story/AB#1235-user-can-view-history` |
| Bug | `bugfix/` | `bugfix/AB#1236-fix-login-redirect` |
| Hot Fix | `hotfix/` | `hotfix/AB#1237-fix-crash-on-submit` |
| (other) | `work/` | `work/AB#1238-update-dependencies` |

> The Azure DevOps work item type is "Hot Fix" (two words), but the branch prefix and PR label use `hotfix` (one word, lowercase).

### Promotion Flow

Code flows through environments via PRs and releases — never by direct push:

```
feature/AB#1234-...  ──PR──▸  main  ──PR──▸  dev  ──PR──▸  test  ──PR──▸  staging  ──PR──▸  prod
   (work branch)            (compare,      (Dev)         (Test)         (Staging)        (Production)
                            no deploy)
```

Releases group work items for coordinated promotion using `/create-release` and `/deploy-release`; `/promote main dev` is the usual first hop.

---

## Current State by Project

### Glasswing and Monarch

| Attribute | Current Value |
|-----------|--------------|
| **Repo** | Glasswing and Monarch |
| **Pipelines** | CD - Development (ID 28) |
| **Pipeline type** | YAML |
| **Trigger branch** | `develop` |
| **Environment branches** | `develop` (Dev only) |
| **Missing branches** | `staging`, production branch not defined |
| **Missing pipelines** | No staging pipeline, no production pipeline |

**Status:** Partially aligned. Has `develop` and a YAML pipeline, but only deploys to Dev. Needs staging and production stages added.

### COMPASS

| Attribute | Current Value |
|-----------|--------------|
| **Repo** | COMPASS |
| **Pipelines** | Compass API (ID 2), Compass Client (ID 3), CSI.Signal (ID 19), PDF Viewer (ID 24) |
| **Pipeline type** | Classic Build + Classic Release (separate) |
| **Trigger branch** | `main` only |
| **Environment branches** | `main` only |
| **Missing branches** | `develop`, `staging` |
| **Feature branch naming** | Ad-hoc (`T3796`, `U3297`, `hf/fdp-verification-on-main`) |
| **Old snapshot branches** | `currentProd`, `Prod-2-9`, `prod-12-19`, etc. |

**Status:** Furthest from target. Uses classic pipelines (not YAML), no environment branches, no promotion flow. Everything goes straight to `main` which deploys to all environments via the Release pipeline.

### CSIPay

| Attribute | Current Value |
|-----------|--------------|
| **Repo** | CSIPay |
| **Pipelines** | CSIPay API (ID 12), CSIPay Client (ID 13) |
| **Pipeline type** | YAML multi-stage |
| **Trigger branches** | `Dev`, `QA`, `Staging`, `master` |
| **Environment branches** | `Dev`, `QA`, `Staging`, `master` |
| **Environments** | Dev, QA, Staging, CSIPayProduction |
| **Deploys to** | IIS on VMs (self-hosted agents) |

**Status:** Closest to target. Already uses YAML multi-stage pipelines with branch-conditional deployment. Needs branch renames (`Dev` → `develop`, `master` → `main`) and eventually QA removal.

---

## Migration Plan: COMPASS

COMPASS requires the most work — converting from classic to YAML and adding environment branches.

### Phase 1: Gather Deployment Info

Before writing the YAML files, the following information is needed for each of the 4 apps (Compass API, Compass Client, CSI.Signal, PDF Viewer):

| Info Needed | Where to Find It |
|-------------|------------------|
| IIS website names per environment (Dev, Staging, Prod) | Classic Release pipeline variables |
| IIS app pool names per environment | Classic Release pipeline variables |
| Physical deploy path on the server | Classic Release pipeline tasks |
| Azure DevOps environment resource names | Classic Release pipeline stages |
| Deployment group / VM agent names | Classic Release pipeline agent settings |
| Any environment-specific variables (connection strings, etc.) | Classic Release pipeline variables per stage |

> **Action:** Open each classic Release pipeline in Azure DevOps portal (`Pipelines > Releases`) and record this info.

### Phase 2: Create YAML Pipeline Files

Use the standard pipeline template included in the AI infrastructure package at `templates/infrastructure/azure-pipelines-template.yml`. Copy it to the COMPASS repo and replace the `{{PLACEHOLDER}}` values with the info from Phase 1. The pattern:

```yaml
# azure-pipelines-api.yml (example structure)
trigger:
  branches:
    include:
      - dev
      - test
      - staging
      - prod
  paths:
    include:
      - Api/**

pool:
  vmImage: "windows-latest"

variables:
  buildConfiguration: "Release"
  projectName: "CompassAPI"
  WebsitePhysicalPath: 'F:\Compass\Api'    # ← from Phase 1

  # Dev
  devWebsiteName: "dev.api.compass.caresolutions.com"    # ← from Phase 1
  devAppPoolName: "dev.api.compass.com"                    # ← from Phase 1

  # Staging
  stagingWebsiteName: "staging.api.compass.caresolutions.com"
  stagingAppPoolName: "staging.api.compass.com"

  # Production
  prodWebsiteName: "api.compass.caresolutions.com"
  prodAppPoolName: "api.compass.com"

stages:
  - stage: Build
    displayName: "Build"
    jobs:
      - job: BuildJob
        steps:
          - script: |
              dotnet build CompassPOC.sln --configuration $(buildConfiguration)
              dotnet publish CompassPOC.sln --configuration $(buildConfiguration) --output $(Build.ArtifactStagingDirectory)
            displayName: "Build and Publish"
          - task: ArchiveFiles@2
            inputs:
              rootFolderOrFile: "$(Build.ArtifactStagingDirectory)"
              includeRootFolder: false
              archiveType: "zip"
              archiveFile: "$(Build.ArtifactStagingDirectory)/$(projectName).zip"
          - publish: $(Build.ArtifactStagingDirectory)/$(projectName).zip
            artifact: drop

  - stage: Dev
    displayName: "Dev"
    dependsOn: "Build"
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/dev'))
    jobs:
      - deployment: DeployDev
        environment:
          name: "Dev"                    # ← from Phase 1
          resourceType: VirtualMachine
        strategy:
          runOnce:
            deploy:
              steps:
                - task: DownloadPipelineArtifact@2
                  inputs:
                    artifact: "drop"
                    path: "$(Build.ArtifactStagingDirectory)"
                - task: IISWebAppManagementOnMachineGroup@0
                  displayName: "Manage IIS Website"
                  inputs:
                    IISDeploymentType: "IISWebsite"
                    ActionIISWebsite: "CreateOrUpdateWebsite"
                    WebsiteName: "$(devWebsiteName)"
                    WebsitePhysicalPath: "$(WebsitePhysicalPath)"
                    WebsitePhysicalPathAuth: "WebsiteUserPassThrough"
                    CreateOrUpdateAppPoolForWebsite: true
                    AppPoolNameForWebsite: "$(devAppPoolName)"
                    DotNetVersionForWebsite: "No Managed Code"
                    PipeLineModeForWebsite: "Integrated"
                    AppPoolIdentityForWebsite: "ApplicationPoolIdentity"
                - task: IISWebAppDeploymentOnMachineGroup@0
                  displayName: "Deploy"
                  inputs:
                    WebsiteName: "$(devWebsiteName)"
                    Package: "$(Build.ArtifactStagingDirectory)/$(projectName).zip"
                    TakeAppOfflineFlag: true
                    XmlVariableSubstitution: true

  - stage: Staging
    displayName: "Staging"
    dependsOn: "Build"
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/staging'))
    jobs:
      - deployment: DeployStaging
        environment:
          name: "Staging"                # ← from Phase 1
          resourceType: VirtualMachine
        strategy:
          runOnce:
            deploy:
              steps:
                # Same pattern as Dev, with staging variables

  - stage: Production
    displayName: "Production"
    dependsOn: "Build"
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/prod'))
    jobs:
      - deployment: DeployProd
        environment:
          name: "CompassProduction"      # ← from Phase 1
          resourceType: VirtualMachine
        strategy:
          runOnce:
            deploy:
              steps:
                # Same pattern as Dev, with production variables
```

Repeat this for each app:
- `azure-pipelines-api.yml` — Compass API (paths: `Api/**`)
- `azure-pipelines-client.yml` — Compass Client (paths: `Client/**`)
- `azure-pipelines-signal.yml` — CSI.Signal (paths: TBD from Phase 1)
- `azure-pipelines-pdf.yml` — PDF Viewer (paths: TBD from Phase 1)

### Phase 3: Create Environment Branches

| Action | Command |
|--------|---------|
| Create `develop` from `main` | `git checkout main && git checkout -b develop && git push -u origin develop` |
| Create `staging` from `main` | `git checkout main && git checkout -b staging && git push -u origin staging` |
| Set `develop` as default branch | Azure DevOps repo settings |

### Phase 4: Create New YAML Pipelines

In Azure DevOps:
1. Go to `Pipelines > New Pipeline`
2. Select the COMPASS repo
3. Point to each YAML file
4. Name them: "Compass API", "Compass Client", "CSI.Signal", "PDF Viewer"

Or via MCP:
```
mcp__azure-devops__pipelines_create_pipeline
```

### Phase 5: Disable Classic Pipelines

1. Disable the old classic Build pipelines (IDs 2, 3, 19, 24)
2. Disable the classic Release pipeline(s)
3. Keep them around (disabled) for a few weeks in case rollback is needed
4. Delete after the new YAML pipelines are proven stable

### Phase 6: Set Branch Policies

| Branch | Policy |
|--------|--------|
| `develop` | Require PR, build validation (YAML pipeline must pass), at least 1 reviewer |
| `staging` | Require PR, build validation, at least 1 reviewer |
| `main` | Require PR, build validation, at least 1 reviewer, approval gate before deploy |

### Phase 7: Clean Up Old Branches

Delete the legacy snapshot branches that are no longer needed:
- `currentProd`, `CurrentApiProd`
- `Prod-2-9`, `prod-12-19`, `hf/prod-2-17`
- `T3856-on-CurrentProd12-5`
- Any merged feature branches (`T3796`, `U3297`, etc.)

---

## Migration Plan: CSIPay

CSIPay is already on YAML multi-stage pipelines. Changes are minimal.

### Now (No Changes)

CSIPay keeps its current 4-environment setup: `Dev → QA → Staging → master`. The slash commands work dynamically with whatever branches exist.

### When QA Is Removed (In a Few Months)

| Step | Action |
|------|--------|
| 1 | Merge any pending work from `QA` to `Staging` |
| 2 | Update `azure-pipelines.yml` — remove `QA` from triggers and delete the QA stage |
| 3 | Update `azure-pipelines-client.yml` — same |
| 4 | Delete the `QA` branch |
| 5 | Remove the QA environment resource from Azure DevOps |

### When Standardizing Branch Names (Optional, Can Be Done Anytime)

| Step | Action |
|------|--------|
| 1 | Create `develop` branch from `Dev` |
| 2 | Create `main` branch from `master` |
| 3 | Update both YAML files — change trigger branches and stage conditions from `Dev`/`master` to `develop`/`main` |
| 4 | Update default branch in repo settings to `main` |
| 5 | Update branch policies to new names |
| 6 | Delete old `Dev` and `master` branches |

**YAML changes needed** (in both `azure-pipelines.yml` and `azure-pipelines-client.yml`):

```yaml
# Before
trigger:
  branches:
    include:
      - Dev
      - QA        # ← remove when QA goes away
      - Staging
      - master

# After (final state)
trigger:
  branches:
    include:
      - dev
      - test
      - staging
      - prod
```

```yaml
# Before
condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/Dev'))
condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/master'))

# After
condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/dev'))
condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/prod'))
```

---

## Migration Plan: Glasswing and Monarch

### Current State

- YAML pipeline "CD - Development" (ID 28) triggers from `develop`
- Deploys to Dev environment only
- No staging or production pipelines

### What's Needed

| Step | Action |
|------|--------|
| 1 | Create `staging` branch from `develop` |
| 2 | Identify or create a production branch (`main`) |
| 3 | Add staging and production stages to the existing YAML pipeline (or create separate pipelines) |
| 4 | Add staging and production deployment targets (Azure App Service or IIS) |
| 5 | Set branch policies on `staging` and production branch |

> **Note:** The Glasswing and Monarch pipeline details need to be reviewed separately. The pipeline YAML is in the repo and can be extended with additional stages following the same pattern as CSIPay.

---

## Slash Commands & Pipeline Integration

The 8 slash commands available after installing the AI infrastructure:

| Command | What It Does | Pipeline Interaction |
|---------|-------------|---------------------|
| `/implement AB#1234` | Create branch, implement, quality checks, PR | No pipeline trigger — pipeline triggers on PR merge |
| `/deploy "message"` | Commit, push, trigger pipeline | Triggers pipeline if on an environment branch |
| `/create-release 23` | Group work items into Release #23 | No pipeline interaction |
| `/deploy-release 23 staging` | Gate-check, cherry-pick release to environment, create PR, advance states after merge | No pipeline trigger — pipeline triggers on PR merge |
| `/cherry-pick AB#1234 prod` | Gate-check, cherry-pick specific work items, create PR, merge it on Serena's approval (`dev`/`test`/`staging` only), advance states after merge | No pipeline trigger — pipeline triggers on PR merge |
| `/promote main dev` | Create PR to promote between environments, merge it on Serena's approval (`dev`/`test`/`staging` only), advance states after merge | No pipeline trigger — pipeline triggers on PR merge (never on `main`) |
| `/rollback AB#1234 prod` | Revert commits, create PR | No pipeline trigger — pipeline triggers on PR merge |
| `/review 142` | Code review a PR | No pipeline interaction |

### CLAUDE.md Pipeline Configuration

Each project should add a pipeline configuration section to its `CLAUDE.md` so the slash commands and deployer agent know which pipelines to trigger and which branches map to which environments:

```markdown
## Pipeline Configuration

| Branch | Environment | Pipeline(s) |
|--------|------------|-------------|
| main | — (compare branch, no deployment) | — |
| dev | Dev | Compass API (YAML) (32), Compass Client (YAML) (33) |
| test | Test | Compass API (YAML) (32), Compass Client (YAML) (33) |
| staging | Staging | Compass API (YAML) (32), Compass Client (YAML) (33) |
| prod | Production | Compass API (YAML) (32), Compass Client (YAML) (33) |
```

This is read by the `/deploy` command and the deployer agent to determine:
- Whether to trigger a pipeline (only on environment branches — never on `main`, whose pipeline cell is `—`)
- Which pipeline ID(s) to trigger
- Which environment the branch maps to

---

## Timeline

| Phase | What | When |
|-------|------|------|
| **Done** | Update AI infrastructure slash commands and docs for the 5-branch layout | 2026-09-06 |
| **Done** | Migrate COMPASS to YAML pipelines (32, 33) + `dev`/`test`/`staging`/`prod` branches | 2026-09 |
| **Done** | Rename CSIPay branches to lowercase; `test` replaces `QA` | 2026-09-04 |
| **Done** | Add `Ready for Staging` / `Staging` states to User Story, Bug, Hot Fix | 2026-09-06 |
| **Next** | Migrate Glasswing and Monarch (`develop` → `dev`, add `test`/`staging`/`prod`, pipeline stages) | Next available sprint |
| **Next** | Confirm CSI.Signal (19) and PDF Viewer (24) are on the new layout | Next available sprint |
| **Ongoing** | New projects use the standard from day one | All new projects |

---

## Reference: CSIPay YAML Pipeline (Working Example)

This is the actual `azure-pipelines.yml` from CSIPay, which serves as the template for converting other projects:

```yaml
trigger:
  branches:
    include:
      - Dev
      - QA
      - Staging
      - master
  paths:
    include:
      - API/**

pool:
  vmImage: "windows-latest"

variables:
  buildConfiguration: "Release"
  projectName: "CSIPayAPI"
  WebsitePhysicalPath: 'F:\CSIPay\Api'

  # Dev
  devWebsiteName: "dev.api.csipay.caresolutions.com"
  devAppPoolName: "dev.api.csipay.com"

  # QA
  qaWebsiteName: "test.api.csipay.caresolutions.com"
  qaAppPoolName: "test.api.csipay.com"

  # Staging
  stagingWebsiteName: "staging.api.csipay.caresolutions.com"
  stagingAppPoolName: "staging.api.csipay.com"

  # Prod
  WebsiteName: "api.csipay.caresolutions.com"
  AppPoolName: "api.csipay.com"

stages:
  - stage: Build
    displayName: "Build the project"
    jobs:
      - job: BuildJob
        displayName: "Build"
        steps:
          - script: |
              dotnet build CSIPay.sln --configuration $(buildConfiguration)
              dotnet publish CSIPay.sln --configuration $(buildConfiguration) --output $(Build.ArtifactStagingDirectory)
            displayName: "Build and Publish with dotnet"
          - task: ArchiveFiles@2
            displayName: "Zip Published Files"
            inputs:
              rootFolderOrFile: "$(Build.ArtifactStagingDirectory)"
              includeRootFolder: false
              archiveType: "zip"
              archiveFile: "$(Build.ArtifactStagingDirectory)/$(projectName).zip"
          - publish: $(Build.ArtifactStagingDirectory)/$(projectName).zip
            artifact: drop

  - stage: Dev
    displayName: "Dev"
    dependsOn: "Build"
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/Dev'))
    jobs:
      - deployment: SetupJob
        displayName: "Deploy Code"
        environment:
          name: "Dev"
          resourceType: VirtualMachine
        strategy:
          runOnce:
            deploy:
              steps:
                - task: DownloadPipelineArtifact@2
                  inputs:
                    artifact: "drop"
                    path: "$(Build.ArtifactStagingDirectory)"
                - task: IISWebAppManagementOnMachineGroup@0
                  displayName: "Manage IIS Website"
                  inputs:
                    IISDeploymentType: "IISWebsite"
                    ActionIISWebsite: "CreateOrUpdateWebsite"
                    WebsiteName: "$(devWebsiteName)"
                    WebsitePhysicalPath: "$(WebsitePhysicalPath)"
                    WebsitePhysicalPathAuth: "WebsiteUserPassThrough"
                    AddBinding: false
                    CreateOrUpdateAppPoolForWebsite: true
                    AppPoolNameForWebsite: "$(devAppPoolName)"
                    DotNetVersionForWebsite: "No Managed Code"
                    PipeLineModeForWebsite: "Integrated"
                    AppPoolIdentityForWebsite: "ApplicationPoolIdentity"
                - task: IISWebAppDeploymentOnMachineGroup@0
                  displayName: "Deploy Site"
                  inputs:
                    WebsiteName: "$(devWebsiteName)"
                    Package: "$(Build.ArtifactStagingDirectory)/$(projectName).zip"
                    TakeAppOfflineFlag: true
                    XmlVariableSubstitution: true

  # QA, Staging, and Production stages follow the same pattern
  # with different branch conditions, environment names, and variables
```

Key patterns:
- **Branch-conditional stages:** Each stage only runs when the build is triggered from the matching branch
- **IIS deployment on VMs:** Uses `IISWebAppManagementOnMachineGroup` and `IISWebAppDeploymentOnMachineGroup`
- **Environment resources:** Azure DevOps environments with `VirtualMachine` resource type (self-hosted agents on the deployment servers)
- **Path filters:** Only triggers when files in the relevant directory change (e.g., `API/**`)
