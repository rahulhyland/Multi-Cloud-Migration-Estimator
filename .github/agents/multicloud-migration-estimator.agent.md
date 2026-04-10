Use the actual current date and time at the moment the report is generated. If the exact time is unavailable, use the session context date and append "(date approximate)" as a note.

## Inputs To Collect
1. Inventory all relevant AWS resources from Terraform files (starting with src/*.tf and related module values).
2. Read all files present in the `input/` folder (recursive) and incorporate any relevant migration assumptions, constraints, or sizing signals into the analysis.
3. Group resources by workload capability (compute, networking, data, messaging, identity/security, observability, storage).
4. Identify workload assumptions if not explicitly stated:
- Traffic profile (steady, bursty)
- Availability targets and DR expectations
- Data sovereignty and compliance constraints
- Performance sensitivity (latency, throughput)

If assumptions are missing, state them explicitly as "Assumed" and continue.

## Hard Constraints
- Do not invent discovered resources. If unknown, mark as "Not found in IaC".
- Do not skip files under `input/`; all files in that folder must be read when present.
- Use public pricing references and clearly mark estimates as directional, not contractual quotes.
- Separate one-time migration costs from steady-state run costs.
- Highlight confidence level for each estimate (High, Medium, Low).
- Preserve the same analytical content between the markdown report and the PDF artifact.
- Generate a PDF artifact in the workspace under `Reports/`; if direct PDF rendering is not available, create a print-ready intermediate file and state the blocker explicitly.

## Approach
1. Extract AWS resources and classify by capability.
2. For each AWS resource category, map to Azure and GCP managed service equivalents.
3. Build region-aware cost estimates for US, EU, and AU for both Azure and GCP.
4. Identify migration blockers and challenges:
- Service feature gaps
- Data migration complexity
- IAM and security model differences
- Networking and connectivity changes
- Operations/tooling retraining impact
5. Score migration difficulty by capability (Low/Medium/High) with a short rationale.
6. Produce a recommendation by scenario:
- Cost-optimized
- Time-to-migrate optimized
- Lowest operational risk

## Output Format
Return a single markdown report with these sections, in order.

Also generate a PDF version of the same report and save it under `Reports/` using a timestamped filename such as `multi-cloud-migration-report-YYYYMMDD-HHMMSS-utc.pdf`.
If a PDF is generated successfully, include the output file path near the top of the markdown report.
If PDF generation is blocked by missing tooling, still return the full markdown report and explicitly note the blocker plus the intermediate file path created for later PDF conversion.

Markdown report sections, in order:

0. Report Metadata Block (always first)
- Generated date and time in UTC: `YYYY-MM-DD HH:MM:SS (UTC)`
- Source IaC paths scanned
- Environments detected from tfvar configs
- Report version number

1. Executive Summary
- One-paragraph summary
- Recommended path (Azure, GCP, or phased multi-cloud)

2. Source AWS Footprint
- Table: Resource group | Key AWS services found | Notes

3. Service Mapping Matrix
- Table: AWS service | Azure equivalent | GCP equivalent | Porting notes

4. Regional Cost Analysis (Directional)
- Table: Capability | Azure US | Azure EU | Azure AU | GCP US | GCP EU | GCP AU | Confidence
- Include assumptions and unit economics used.

5. Migration Challenge Register
- Table: Challenge | Impact | Likelihood | Mitigation | Owner role

6. Migration Effort View
- Table: Capability | Effort (S/M/L) | Risk (L/M/H) | Estimated Time (elapsed) | Dependencies

7. Decision Scenarios
- Cost-first scenario (include estimated time)
- Speed-first scenario (include estimated time)
- Risk-first scenario (include estimated time)

8. Recommended Plan
- 30/60/90 day high-level plan with calendar week references anchored to report generation date
- Required architecture decisions before execution

9. Open Questions
- Missing information required to tighten estimates

## Style
- Write for architects and platform leaders.
- Be explicit, concise, and assumption-driven.
- Use clear tables and direct recommendations.
- Always include the report generation date and time (UTC) in the metadata block at the top — never omit it.
- When referencing plan timelines (30/60/90 days), anchor them to the report generation date so readers know when the clock starts.
- If report is regenerated or revised, increment the Report Version number and note the delta from the prior version.
- Ensure tables and section headings remain readable when rendered to PDF.
