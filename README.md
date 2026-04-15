# Multi-Cloud Migration Estimator Agent

This folder contains a custom Copilot agent used to estimate AWS to Azure and GCP migration effort, regional cost (US, EU, AU), and architect decision guidance.

## Files

- `.github/agents/multicloud-migration-estimator.agent.md`: Agent definition with complete workflow, guardrails, and report generation logic.
- `.vscode/mcp.json`: GitHub MCP server configuration for GitHub API integration.
- `Reports/`: Generated migration decision report artifacts. Each run creates a timestamped subfolder containing the markdown report, six draw.io files (one per SVG), and SVG exports (three architecture SVGs + three chart SVGs, all mandatory).

## What This Agent Does

The agent analyzes Terraform from either local cloned repository paths or remote GitHub repositories and produces a migration report with:

- AWS source footprint summary
- Azure and GCP service mapping
- Directional regional cost analysis (US, EU, AU) with AWS baseline, explicit currency labels, 30-day total run-rate, metered billing tiers, and one-time migration versus run-rate comparison
- Migration challenge and risk register
- Effort scoring and a dynamic implementation timeline based on discovered infrastructure complexity
- Open questions for architects
- Component diagrams delivered as dedicated draw.io artifacts (AWS source, Azure target, GCP target), with one draw.io file per SVG output, saved in a per-run timestamped folder under `Reports/`
- Mandatory supplemental draw.io chart artifacts: cost comparison, effort-risk, and scenario comparison, each with a matching SVG in the same per-run folder

## How To Use

1. Open Copilot Chat in VS Code.
2. Select the agent named `Multi-Cloud Migration Estimator`.
3. Provide your scope and assumptions.
4. Ask for a report.

## Recommended Prompt Input

Use this template when running the agent:

### Local Cloned Repositories

```text
Create a migration decision report by fetching Terraform files from these repositories:
- /Users/name/code/service-api
- /Users/name/code/platform-infra

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
2. Source Repository Inventory
3. Source AWS Footprint
4. Service Mapping Matrix
5. Regional Cost Analysis (Directional)
6. Migration Challenge Register
7. Migration Effort View
8. Decision Scenarios
9. Recommended Plan (Dynamic Timeline)
10. Open Questions
11. Component Diagrams (embedded SVG diagrams and page mapping)

Notes:
- The markdown report is saved in a new run folder: `Reports/multi-cloud-migration-YYYYMMDD-HHMMSS-utc/`.
- SVG files are embedded in their corresponding sections throughout the report:
  - **Section 5 (Regional Cost Analysis):** Cost comparison chart SVG
   - **Section 7 (Migration Effort View):** Effort-risk chart SVG
   - **Section 8 (Decision Scenarios):** Scenario comparison chart SVG
  - **Section 11 (Component Diagrams):** Architecture diagrams (AWS Source, Azure Target, GCP Target)
- Each SVG is embedded exactly once in the markdown report (no duplicate embeddings across sections).
- Total SVG references in the markdown report must be 6 (3 architecture diagrams + 3 charts).
- SVG files are saved as `diagrams-{aws-source|azure-target|gcp-target|cost-comparison|effort-risk|scenario-comparison}.svg` inside the run folder under `Reports/`.
- Cost outputs explicitly label currency (default `USD`) wherever cost is shown.
- Section 5 includes AWS baseline pricing for comparison in the 30-day cost table, metered tier table, and one-time migration versus run-rate table.
- Section 9 uses a complexity-based timeline such as `30/60`, `30/60/90`, or `30/60/90/120` instead of forcing a fixed `30/60/90` structure.
- The markdown report references diagram files using markdown image embeds only in section 11 (no separate SVG path listing).
- The markdown report embeds all three SVG files directly in section 11 using markdown image syntax.
- SVG files are saved as `diagrams-{aws-source|azure-target|gcp-target}.svg` inside the run folder under `Reports/`.
- Draw.io/SVG diagrams must be detailed (Mermaid-equivalent logical architecture), not just high-level capability boxes.
- SVG outputs must be standards-compliant and browser-renderable (no raw `mxGraphModel` embedded inside `<svg>`).
- SVG arrows and labels should use explicit high-contrast styling for both light and dark mode (highlighted arrows, visible arrowheads, readable font fill/outline).
- Chat responses should confirm markdown and draw.io artifact path(s) only; SVG paths are embedded inline in their corresponding report sections.
- AWS diagram should explicitly show: clients, DNS/ingress, EKS boundary, REST, router, engines, KEDA, network policies, Kubernetes secrets, SQS/SNS, KMS, Secrets Manager, Datadog, and VPC/subnets (or mark missing items as `Not found in IaC`).
- Azure and GCP diagrams should use equivalent granularity and explicit service-to-service flows.
- Mermaid blocks are not embedded in the markdown report.

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

The agent file (`.github/agents/multicloud-migration-estimator.agent.md`) includes `"mcp:github"` in its `tools` list and is also allowed to use terminal execution:

```yaml
tools: [read, search, edit, web, execute, "mcp:github"]
```

This grants the agent access to all tools exposed by the GitHub MCP server and allows it to run local publish/build commands when terminal execution is available. To restrict MCP access to specific tools, use the format `"mcp:github:tool_name"` (e.g., `"mcp:github:create_issue"`).

### Available Capabilities

Once connected, the agent can:

| Capability              | Example Use Case                                                   |
| ----------------------- | ------------------------------------------------------------------ |
| **Create issues**       | File tracking issues from the Open Questions or Challenge Register |
| **Search repositories** | Find reference IaC patterns in other repos                         |
| **Read repo files**     | Pull Terraform modules or Helm charts from remote repos            |
| **Create/manage PRs**   | Open a PR with the generated migration report                      |
| **List branches/tags**  | Discover environment branches for IaC discovery                    |

### Verifying the Integration

1. Ensure `.env` contains a valid PAT.
2. Open VS Code and reload the window (`Cmd+Shift+P` → `Developer: Reload Window`).
3. Open Copilot Chat and select the **Multi-Cloud Migration Estimator** agent.
4. Ask: _"List open issues in this repo"_.
5. The agent should return results from the GitHub API.

### Troubleshooting MCP

| Symptom                          | Fix                                                                                            |
| -------------------------------- | ---------------------------------------------------------------------------------------------- |
| `npx` not found                  | Ensure Node.js is installed and `npx` is on your `PATH`                                        |
| Auth errors (401/403)            | Check your PAT in `.env` has the required scopes (`repo`, `read:org`)                          |
| **404 on private repos**         | Your PAT needs `repo` scope (not just `public_repo`). Update `.env` and restart the MCP server |
| **`.env` not found error**       | Run `cp .env.example .env` and fill in your token                                              |
| MCP tools not available to agent | Confirm `"mcp:github"` is in the `tools` list in the agent file                                |
| Server not starting              | Check the **Output** panel → **MCP** for server logs                                           |
| Timeout on first run             | First `npx` invocation downloads the package; retry after it completes                         |

## Atlassian Confluence Integration

The agent can optionally publish generated migration reports to Atlassian Confluence after saving them locally.

### Prerequisites

- `.env` contains valid Atlassian credentials.
- You have write access to the configured shared Confluence space.
- The repository publish script is available at `scripts/publish-to-confluence.sh`.

### Configuration

1. Open `.env` and add your Atlassian credentials (these are in addition to your GitHub token):

   ```ini
   ATLASSIAN_API_EMAIL=your_email@company.com
   ATLASSIAN_API_TOKEN=your_api_token_here
   ATLASSIAN_API_ENDPOINT=https://your-instance.atlassian.net
   ATLASSIAN_SPACE_KEY=ENG
   ```

2. Verify your workspace has a valid `.env` with all four variables filled in.
3. The `.env` file is gitignored and should never be committed.

### How Publishing Works

When you ask the agent to publish a report to Confluence and terminal execution is available:

1. The agent generates and saves the report locally under `Reports/`.
2. The agent runs `./scripts/publish-to-confluence.sh` from the workspace root.
3. The script auto-detects the latest report, resolves the configured Confluence space from `ATLASSIAN_SPACE_KEY`, and creates or updates the corresponding page.
4. The script returns the page title, page ID, local report filename, and final URL.
5. The agent relays those results back to you.

If terminal execution is unavailable, the agent should provide the exact publish command and the expected output format instead of claiming to publish directly.

### Example Usage

After the agent generates a migration report:

```text
Publish this report to Confluence.
```

Or explicitly:

```text
Create a migration decision report for this repo, then publish it to Confluence.
```

### Expected Script Output

```text
SUCCESS
Title: Migration Report - 2026-04-14 12:30 UTC
Page ID: 4031226486
Local file: report.md
URL: https://hyland.atlassian.net/wiki/spaces/ENG/pages/4031226486/...
```

### Available Capabilities

| Capability | Status | Notes |
|---|---|---|
| **Create page** | ✓ | Script creates a new page when no title match exists |
| **Update page** | ✓ | Script updates an existing page safely when the title already exists |
| **Shared-space publishing** | ✓ | Uses `ATLASSIAN_SPACE_KEY` to target a team-visible space |
| **Direct agent execution** | ✓ | Agent runs the script when terminal execution is available |

### Error Handling

| Error                | Cause                          | Fix                                                                |
| -------------------- | ------------------------------ | ------------------------------------------------------------------ |
| **401 Unauthorized** | Invalid credentials in `.env` | Verify email, token, and endpoint values in `.env` |
| **403 Forbidden** | No write permission in target space | Check the shared space configured by `ATLASSIAN_SPACE_KEY` |
| **Space not found** | Invalid or inaccessible space key | Verify `ATLASSIAN_SPACE_KEY` refers to an existing writable space |
| **Permission denied** | Confluence write access missing | Confirm your Atlassian account can create/update pages in the target space |

### Troubleshooting Authentication

1. Verify the API token at [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens).
2. Check `.env` formatting and ensure `ATLASSIAN_API_EMAIL`, `ATLASSIAN_API_TOKEN`, `ATLASSIAN_API_ENDPOINT`, and `ATLASSIAN_SPACE_KEY` are present.
3. Run the publish script manually if needed:

   ```bash
   ./scripts/publish-to-confluence.sh
   ```

4. If the script fails, validate that the target shared space exists and that you have write permission.

### Opting Out

Confluence publishing is **optional**. If you don't configure `.env` with Atlassian credentials:

- The agent still generates and saves reports locally to `Reports/`.
- Confluence publishing will be skipped or fail gracefully.
- All core migration analysis functionality remains available.

## Troubleshooting

- Agent not showing in picker: verify YAML frontmatter is valid and file path is `.github/agents/*.agent.md`.
- Agent not selected automatically: improve `description` with clear trigger phrases.
- Output missing sections: check `Output Format` section and section numbering.
- Inconsistent costs: ensure assumptions are provided and confidence labels are included.
