Implement work item AB#$ARGUMENTS. Follow this workflow:

1. **Read the work item** from Azure DevOps via MCP — understand all acceptance criteria
2. **Explore** the codebase to map relevant files
3. **Plan** the implementation approach
4. **Implement** using backend and/or frontend agents
5. **Generate mockup** if there are UI changes
6. **Review** code for quality, security, and Clean Architecture compliance
7. **Run tests** — unit, integration, and build validation
8. **Run lint** — ESLint and dotnet format
9. **Generate UAT checklist** from the acceptance criteria

After all automated checks pass, STOP and present:

```
Automated checks passed and the UAT checklist is ready.

## UAT Checklist
[generated checklist here]

Please manually test the feature using the checklist above.

Did manual testing pass?
- If YES → reply "testing passed" and I will create the PR
- If NO  → describe what failed or what behaved unexpectedly
           and I will investigate and fix before asking you again
```

Wait for the user's response before proceeding. Do NOT create a PR until manual testing is confirmed.

If testing passed:
1. Create a PR with a clear title and description linking to AB#$ARGUMENTS
2. Update the work item status in Azure DevOps
