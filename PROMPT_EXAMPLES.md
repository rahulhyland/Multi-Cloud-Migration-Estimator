# Prompt Examples

Use these prompts with the `Multi-Cloud Migration Estimator` agent in Copilot Chat.

## Abbreviation Guide

- AWS: Amazon Web Services
- GCP: Google Cloud Platform
- IaC: Infrastructure as Code
- API: Application Programming Interface
- RTO: Recovery Time Objective
- RPO: Recovery Point Objective
- SOC 2: System and Organization Controls 2
- GDPR: General Data Protection Regulation
- HIPAA: Health Insurance Portability and Accountability Act

## 1. Local Repositories: Standard Assessment

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
- RTO (Recovery Time Objective): 4 hours.
- RPO (Recovery Point Objective): 30 minutes.
- Compliance: SOC 2 (System and Organization Controls 2) + regional data residency.
- Performance: latency sensitive APIs (Application Programming Interfaces).
```

## 2. Remote GitHub Repositories: Multi-Repo Assessment

```text
Create a migration decision report by fetching Terraform files from these repositories:
- https://github.com/org/service-api
- https://github.com/org/data-platform
- https://github.com/org/infra-modules

Use the main branch for all repos.
Look for .tf files in src/, infra/, terraform/, and infrastructure/ directories.
Planning horizon: 24 months.
Assumptions:
- Traffic profile: steady with moderate burst.
- Availability target: 99.9%.
- RTO (Recovery Time Objective): 4 hours.
- RPO (Recovery Point Objective): 30 minutes.
- Compliance: SOC 2 (System and Organization Controls 2) + regional data residency.
- Performance: latency sensitive APIs (Application Programming Interfaces).
```

## 3. Mixed Local + GitHub Sources

```text
Create a migration decision report by fetching Terraform files from these repositories:
- /Users/name/code/hxpr-aws-infrastructure
- https://github.com/org/hxpr-app-platform

Use the main branch for all repos.
Prefer local files when both local and remote copies exist.
Look for .tf files in src/, infra/, terraform/, iac/, and deploy/ directories.
Planning horizon: 18 months.
Assumptions:
- Traffic profile: steady with seasonal burst.
- Availability target: 99.95%.
- RTO (Recovery Time Objective): 2 hours.
- RPO (Recovery Point Objective): 15 minutes.
- Compliance: SOC 2 (System and Organization Controls 2) + GDPR (General Data Protection Regulation) + regional data residency.
- Performance: latency sensitive APIs (Application Programming Interfaces) with background async jobs.
```

## 4. Cost-Focused Migration Review

```text
Create a migration decision report by fetching Terraform files from these repositories:
- /Users/name/code/customer-platform

Use the main branch.
Look for .tf files in src/, infra/, terraform/, and **/*.tfvars.
Planning horizon: 36 months.
Assumptions:
- Traffic profile: steady with moderate burst.
- Availability target: 99.9%.
- RTO (Recovery Time Objective): 8 hours.
- RPO (Recovery Point Objective): 4 hours.
- Compliance: SOC 2 (System and Organization Controls 2).
- Performance: moderate API (Application Programming Interface) latency sensitivity.

Prioritize the report for cost optimization.
Call out the cheapest Azure-first path, the cheapest GCP-first path, and the break-even point versus AWS baseline.
```

## 5. Risk-Focused Migration Review

```text
Create a migration decision report by fetching Terraform files from these repositories:
- /Users/name/code/document-platform
- /Users/name/code/shared-infra

Use the main branch for all repos.
Look for .tf files in src/, infra/, terraform/, and helm/ directories.
Planning horizon: 24 months.
Assumptions:
- Traffic profile: bursty during business hours.
- Availability target: 99.99%.
- RTO (Recovery Time Objective): 1 hour.
- RPO (Recovery Point Objective): 5 minutes.
- Compliance: SOC 2 (System and Organization Controls 2) + HIPAA (Health Insurance Portability and Accountability Act) + regional data residency.
- Performance: latency sensitive APIs (Application Programming Interfaces) and search-heavy workloads.

Prioritize the report for migration risk reduction.
Recommend the safest timeline, key cutover gates, and the highest-risk services to migrate.
```

## 6. Generate And Publish

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
- RTO (Recovery Time Objective): 4 hours.
- RPO (Recovery Point Objective): 30 minutes.
- Compliance: SOC 2 (System and Organization Controls 2) + regional data residency.
- Performance: latency sensitive APIs (Application Programming Interfaces).

After generating the report, publish it to Confluence.
```

## Tips

- Provide exact local paths when possible so the agent can prioritize local IaC (Infrastructure as Code) over remote copies.
- Include usage assumptions if you want more credible directional cost outputs.
- Add a line such as `Prioritize the report for cost optimization` or `Prioritize the report for migration risk reduction` when you want a clear bias in the recommendation.
- If you want publishing, ask for it explicitly in the same prompt or as a follow-up.