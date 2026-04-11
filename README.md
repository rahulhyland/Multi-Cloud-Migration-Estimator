# Multi-Cloud Migration Estimator Agent

This folder contains a custom Copilot agent used to estimate AWS to Azure and GCP migration effort, regional cost (US, EU, AU), and architect decision guidance.

## Files
- `.github/agents/multicloud-migration-estimator.agent.md`: Agent definition (frontmatter + behavior).
- `.github/skills/multicloud-migration-estimator/SKILL.md`: Reusable skill workflow and guardrails for report generation.
- `.vscode/mcp.json`: GitHub MCP server configuration for GitHub API integration.
- `Multi-Cloud Migration Decision Report.pdf`: Example generated report artifact (optional output).

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
Edit `.github/agents/multicloud-migration-estimator.agent.md`.

## How To Update The Skill
Edit `.github/skills/multicloud-migration-estimator/SKILL.md` when changing discovery scope, workflow, or report guardrails.

### 1) Update discovery and invocation metadata
In YAML frontmatter:
- `name`: Display name in agent picker.
- `description`: Discovery trigger text. Keep specific keywords.
- `tools`: Keep minimal required tools.
- `argument-hint`: Input guidance shown to users.

### 2) Update behavior safely
In body sections:
- `Objective`: Keep scope clear (AWS source, Azure/GCP target).
- `Hard Constraints`: Keep non-negotiables (no invented resources, directional cost only, confidence levels).
- `Approach`: Keep extraction -> mapping -> costing -> risk -> recommendation flow.
- `Output Format`: Keep section order stable for stakeholder consistency.

### 3) Validate after edits
1. Start a new chat.
2. Invoke the agent with a small scope request.
3. Confirm report contains all required sections.
4. Confirm unknowns are marked as assumptions or missing IaC facts.
5. Check cost outputs are clearly labeled directional.

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

The MCP server is configured in [`.vscode/mcp.json`](.vscode/mcp.json):

```json
{
  "servers": {
    "github": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${input:github_pat}"
      }
    }
  },
  "inputs": [
    {
      "id": "github_pat",
      "type": "promptString",
      "description": "GitHub Personal Access Token",
      "password": true
    }
  ]
}
```

VS Code will prompt for your PAT on first use. The token is not stored in the file.

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

1. Open VS Code and reload the window (`Cmd+Shift+P` → `Developer: Reload Window`).
2. Open Copilot Chat and select the **Multi-Cloud Migration Estimator** agent.
3. Ask: _"List open issues in this repo"_.
4. If prompted for a PAT, enter your token.
5. The agent should return results from the GitHub API.

### Troubleshooting MCP

| Symptom | Fix |
|---|---|
| `npx` not found | Ensure Node.js is installed and `npx` is on your `PATH` |
| Auth errors (401/403) | Regenerate your PAT with the required scopes (`repo`, `read:org`) |
| MCP tools not available to agent | Confirm `"mcp:github"` is in the `tools` list in the agent file |
| Server not starting | Check the **Output** panel → **MCP** for server logs |
| Timeout on first run | First `npx` invocation downloads the package; retry after it completes |

## Troubleshooting
- Agent not showing in picker: verify YAML frontmatter is valid and file path is `.github/agents/*.agent.md`.
- Agent not selected automatically: improve `description` with clear trigger phrases.
- Output missing sections: check `Output Format` section and section numbering.
- Inconsistent costs: ensure assumptions are provided and confidence labels are included.

