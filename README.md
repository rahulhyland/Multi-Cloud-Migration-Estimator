# Multi-Cloud Migration Estimator Agent

This folder contains a custom Copilot agent used to estimate AWS to Azure and GCP migration effort, regional cost (US, EU, AU), and architect decision guidance.

## Files
- `.github/agents/multicloud-migration-estimator.agent.md`: Agent definition with complete workflow, guardrails, and report generation logic.
- `.vscode/mcp.json`: GitHub MCP server configuration for GitHub API integration.
- `Reports/`: Generated migration decision report artifacts (markdown format with timestamp).

## What This Agent Does
The agent analyzes files under `input/**` (prioritizing IaC from `input/**/src/*.tf`) and produces a migration report with:
- AWS source footprint summary
- Azure and GCP service mapping
- Directional regional cost analysis (US, EU, AU)
- Migration challenge and risk register
- Effort scoring and 30/60/90 day plan
- Open questions for architects

## How To Use
1. Open Copilot Chat in VS Code.
2. Select the agent named `Multi-Cloud Migration Estimator`.
3. Provide your scope and assumptions.
4. Ask for a report.

## Recommended Prompt Input
Use this template when running the agent:

### Local Files
```text
Create a migration decision report for this repo.
Scope: input/**/src/*.tf, all environments.
Planning horizon: 24 months.
Assumptions:
- Traffic profile: steady with moderate burst.
- Availability target: 99.9%.
- RTO: 4 hours.
- RPO: 30 minutes.
- Compliance: SOC2 + regional data residency.
- Performance: latency sensitive APIs.
```

### Remote Repositories (Multi-Repo)
```text
Create a migration decision report by fetching Terraform files from these repositories:
- https://github.com/org/service-api
- https://github.com/org/data-platform
- https://github.com/org/infra-modules

Use the main branch for all repos.
Look for .tf files in src/, infra/, and terraform/ directories.
Planning horizon: 24 months.
Assumptions:
- Traffic profile: steady with moderate burst.
- Availability target: 99.9%.
- RTO: 4 hours.
- RPO: 30 minutes.
- Compliance: SOC2 + regional data residency.
- Performance: latency sensitive APIs.
```

## Expected Output Sections
The report is expected to include these sections:
1. Executive Summary
2. Source AWS Footprint
3. Service Mapping Matrix
4. Regional Cost Analysis (Directional)
5. Migration Challenge Register
6. Migration Effort View
7. Decision Scenarios
8. Recommended Plan (30/60/90)
9. Open Questions

## How To Update The Agent
Edit `.github/agents/multicloud-migration-estimator.agent.md` to modify discovery scope, workflow, report format, or guardrails.

All agent behavior, discovery logic, and report generation instructions are contained within the agent file. No external skill dependencies exist.

## Improvement
Current approach: we use a single agent, so all workflow and guardrails are intentionally centralized in one agent file for simpler maintenance.

Future scaling approach: if we introduce multiple agents, we can extract shared logic into one reusable skill file and have each agent reference that same skill to avoid duplication and keep behavior consistent.

## Common Update Patterns

### Add a new target region
- Update `Approach` and `Output Format` cost table columns.
- Mention the region explicitly in `description` if discoverability matters.

### Add a new cloud target
- Update all references from "Azure and GCP" to include the new cloud.
- Extend the Service Mapping Matrix and cost table columns.
- Add cloud-specific risk items to migration challenges.

### Tighten governance/compliance requirements
- Add requirements under `Hard Constraints`.
- Add explicit checks in `Approach` and `Open Questions`.

## Authoring Guidelines
- Keep instructions explicit and testable.
- Avoid vague wording like "best effort" without criteria.
- Keep output format stable to avoid report drift across runs.
- Prefer additive updates over full rewrites.

## Versioning And Review
When updating this agent in a pull request:
- Summarize what changed in prompt behavior.
- Include one before/after sample prompt.
- Include one sample output delta (section-level is enough).
- Request review from platform and architecture stakeholders.

## GitHub MCP Server Integration

The agent integrates with the [GitHub MCP server](https://github.com/modelcontextprotocol/servers/tree/main/src/github) to interact with GitHub APIs (issues, PRs, repos, search) directly from Copilot Chat.

### Prerequisites
- **Node.js** (v18+) — required currently to run the MCP server via `npx`.
- **GitHub Personal Access Token** — create one at **Settings → Developer settings → Personal access tokens** with scopes: `repo`, `read:org`.

### Configuration

1. Copy the `.env.example` file to `.env`:
   ```sh
   cp .env.example .env
   ```
2. Edit `.env` and replace `your_token_here` with your GitHub PAT:
   ```
   GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
   ```
3. The `.env` file is gitignored and will **not** be committed.

The MCP server is configured in [`.vscode/mcp.json`](.vscode/mcp.json):

```json
{
  "servers": {
    "github": {
      "type": "stdio",
      "command": "sh",
      "args": [
        "-c",
        "set -a && . '${workspaceFolder}/.env' && set +a && npx -y @modelcontextprotocol/server-github"
      ]
    }
  }
}
```

The server sources the `.env` file at startup — no interactive prompt needed.

### How It Connects to the Agent

The agent file (`.github/agents/multicloud-migration-estimator.agent.md`) includes `"mcp:github"` in its `tools` list:

```yaml
tools: [read, search, edit, web, "mcp:github"]
```

This grants the agent access to all tools exposed by the GitHub MCP server. To restrict to specific tools, use the format `"mcp:github:tool_name"` (e.g., `"mcp:github:create_issue"`).

### Available Capabilities

Once connected, the agent can:

| Capability | Example Use Case |
|---|---|
| **Create issues** | File tracking issues from the Open Questions or Challenge Register |
| **Search repositories** | Find reference IaC patterns in other repos |
| **Read repo files** | Pull Terraform modules or Helm charts from remote repos |
| **Create/manage PRs** | Open a PR with the generated migration report |
| **List branches/tags** | Discover environment branches for IaC discovery |

### Verifying the Integration

1. Ensure `.env` contains a valid PAT.
2. Open VS Code and reload the window (`Cmd+Shift+P` → `Developer: Reload Window`).
3. Open Copilot Chat and select the **Multi-Cloud Migration Estimator** agent.
4. Ask: _"List open issues in this repo"_.
5. The agent should return results from the GitHub API.

### Troubleshooting MCP

| Symptom | Fix |
|---|---|
| `npx` not found | Ensure Node.js is installed and `npx` is on your `PATH` |
| Auth errors (401/403) | Check your PAT in `.env` has the required scopes (`repo`, `read:org`) |
| **404 on private repos** | Your PAT needs `repo` scope (not just `public_repo`). Update `.env` and restart the MCP server |
| **`.env` not found error** | Run `cp .env.example .env` and fill in your token |
| MCP tools not available to agent | Confirm `"mcp:github"` is in the `tools` list in the agent file |
| Server not starting | Check the **Output** panel → **MCP** for server logs |
| Timeout on first run | First `npx` invocation downloads the package; retry after it completes |

## Troubleshooting
- Agent not showing in picker: verify YAML frontmatter is valid and file path is `.github/agents/*.agent.md`.
- Agent not selected automatically: improve `description` with clear trigger phrases.
- Output missing sections: check `Output Format` section and section numbering.
- Inconsistent costs: ensure assumptions are provided and confidence labels are included.

