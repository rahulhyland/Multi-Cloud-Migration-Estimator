# Multi-Cloud Migration Decision Report

## 1. Executive Summary

The analyzed AWS IaC footprint across the three repositories shows a Kubernetes-centric transformation platform (HxTS) built on EKS, SQS/SNS queue-driven messaging, ALB/WAF edge protection, Route53/ACM DNS/TLS, EFS and S3-backed storage and backup (Velero), KMS-at-rest encryption, and Datadog-centred observability. The system runs across five environments (sandbox, dev, staging, prod us-east-1, prod-eu eu-central-1) with KEDA queue-depth autoscaling, Karpenter node provisioning, and an IRSA-based workload identity model. For a 24-month horizon against 99.9% availability, RTO 4h, RPO 30m, SOC2 plus regional residency, and latency-sensitive APIs, **Azure is recommended as the primary target** due to closer managed-service parity for queue-driven autoscaling, enterprise operational guardrails, and EU data residency alignment. GCP is the cost-optimised alternative and should be benchmarked in parallel during the first 30 days before the final platform decision is locked.

## 2. Source Repository Inventory

| Repository | Branch | Scope | IaC signal found | Notes |
|---|---|---|---|---|
| HylandSoftware/hxp-transform-service | main | src/, infra/, terraform/ | Application-level AWS SDK usage (SQS/SNS/S3), Helm deployment docs, KEDA ScaledObject config, EFS/PVC references | No standalone Terraform modules in requested paths; IaC owned by infrastructure repos. |
| HylandSoftware/terraform-aws-hxts-environment | main | src/, infra/, terraform/ | ~25–35 TF/tfvars files confirmed | Root TF module: SQS queues (~28/env), KMS per-env key, Helm releases (hxts + keda-scalers), network policies, Datadog monitors. tfvars for sandbox/dev/staging/prod/prod-eu. |
| HylandSoftware/tf-cfg-hxts-infrastructure | main | src/, infra/, terraform/ | ~50–70 TF/tfvars files confirmed | EKS v1.33, Karpenter 1.10.0, cert-manager v1.20.0, Velero 11.4.0, KEDA 2.17, shared SNS topics, ALB + WAFv2, Route53, ACM, EFS CMK, EBS CMK, Velero S3 cross-region buckets. |

Assumed: Exact recursive file counts are directional; remote search returns content evidence rather than a full directory listing.

## 3. Source AWS Footprint

| Resource group | Key AWS services found | Notes |
|---|---|---|
| Compute | EKS v1.33, EC2 managed node groups (m5.xlarge), Karpenter 1.10.0 (Bottlerocket nodes) | Min 2–3, max 10–25 nodes per environment. ON_DEMAND capacity type. |
| Networking | VPC (10.17.0.0/18, 3 AZs), ALB, NLB (private), Route53, ACM wildcard certs, WAFv2 | Public ALB fronts private NLB. WAF uses AWSManagedRulesCommonRuleSet with custom overrides. |
| Data | EFS (elastic throughput, KMS CMK), EBS (gp3, KMS CMK), S3 (Velero backup buckets, cross-region replication) | EFS shared PVC at /tmp/filestore-shared across engine pods. |
| Messaging | SQS (28 queues/env, KMS-encrypted, 4-day retention), SNS (transform-request, transform-reply topics) | FIFO-style routing via MessageGroupId; queue-depth triggers KEDA scaling per engine. |
| Identity / Security | IAM, IRSA/OIDC, KMS (per-env + shared), Secrets Manager (/hxts/idp_client_secret), Access Analyzer, Network ACLs | GitHub OIDC federation for CI/CD. Cross-account SNS subscribe permissions for HxPR. |
| Observability | Datadog (DaemonSet + Java agent v1.60.1), CloudWatch (EKS control-plane log export on prod) | Structured JSON logging via Logstash encoder. PagerDuty on prod P1/P2. |
| Storage / Backup | EFS, S3 (primary us-east-1 + backup us-west-2 for Velero; eu-central-1 + eu-west-1 for prod-eu) | Velero IRSA role scoped to per-env S3 buckets. |

## 4. Service Mapping Matrix

| AWS service | Azure equivalent | GCP equivalent | Porting notes |
|---|---|---|---|
| EKS v1.33 | AKS | GKE (Autopilot or Standard) | Minimal app-code changes; node pool, IAM model, and ingress-class refactor required. |
| EC2 node groups + Karpenter | VMSS + AKS Node Autoprovision / Karpenter for AKS (preview) | GKE Node Pools + cluster autoscaler | Provisioning semantics and workload placement rules must be re-expressed. |
| SQS (standard queues, 28/env) | Azure Service Bus queues | Pub/Sub pull subscriptions (or Cloud Tasks for point-to-point) | Dead-letter, visibility-timeout, and at-least-once delivery semantics need contract tests. |
| SNS (fanout topics) | Service Bus topics + subscriptions | Pub/Sub topics + subscriptions | SNS filter policies map to Service Bus SQL filters; cross-account model replaced by Entra/IAM bindings. |
| ALB + NLB | Application Gateway v2 + Azure Load Balancer | Google Cloud HTTPS Load Balancer + ILB | Ingress class, health-probe paths, and SSL policy migration required. |
| WAFv2 | Azure WAF (App Gateway / Front Door) | Cloud Armor | Rule parity achievable; custom exclusions for binary upload routes must be revalidated. |
| Route53 | Azure DNS | Cloud DNS | Zone and record migration straightforward; requires controlled TTL-lowering cutover. |
| ACM wildcard certs | Key Vault certificates + cert-manager | Certificate Manager | cert-manager already present in cluster; swap ACME issuer and Key Vault integration. |
| EFS (NFS, elastic throughput) | Azure Files (NFS) / Azure NetApp Files | Filestore | Throughput and mount-latency benchmark required; latency-sensitive API paths depend on EFS. |
| S3 (Velero backup) | Azure Blob Storage | Cloud Storage | Velero has native Azure/GCP plugins; backup bucket policy and cross-region replication to be re-expressed. |
| KMS (CMK per-env) | Key Vault Managed HSM / Keys | Cloud KMS CMEK | CMK key hierarchy and rotation policies require redesign per target IAM model. |
| Secrets Manager | Key Vault secrets | Secret Manager | Secret naming, rotation, and injection pipeline changes. External Secrets Operator recommended for Kubernetes integration. |
| Datadog + CloudWatch | Azure Monitor + Datadog | Cloud Operations + Datadog | Retain Datadog to minimise retraining cost and preserve existing dashboards and monitors. |
| IRSA / OIDC | Azure Workload Identity (AKS) | GKE Workload Identity | Federation patterns differ; IRSA policies map to Entra app registrations or GKE SA bindings. |
| Velero 11.4.0 | Velero with Azure plugin | Velero with GCP plugin | Plugin swap; S3 backend replaced by Blob/GCS; cross-region replication strategy recreated. |

## 5. Regional Cost Analysis (Directional)

Directional monthly run-rate estimate in USD for comparable steady-state capacity. **Not a vendor quote — all figures are directional estimates.**

| Capability | Azure US | Azure EU | Azure AU | GCP US | GCP EU | GCP AU | Confidence |
|---|---:|---:|---:|---:|---:|---:|---|
| Compute (managed K8s control plane + m5-equivalent nodes) | 25,000 | 27,500 | 29,800 | 24,200 | 26,300 | 29,100 | Medium |
| Networking + Edge (LB, WAF, DNS, egress) | 4,800 | 5,300 | 5,900 | 4,500 | 5,000 | 5,700 | Low |
| Messaging (queue/topic operations, ~28 queues × 5 envs) | 3,200 | 3,450 | 3,900 | 2,900 | 3,250 | 3,700 | Medium |
| Data + Storage (file, object, backup, cross-region rep) | 6,900 | 7,400 | 8,100 | 6,400 | 6,900 | 7,800 | Medium |
| Security + Identity + Keys (KMS/Key Vault, Secrets) | 1,450 | 1,600 | 1,750 | 1,300 | 1,500 | 1,680 | Low |
| Observability (Datadog retained + platform monitoring) | 5,200 | 5,600 | 6,000 | 5,100 | 5,500 | 5,900 | Medium |
| **Total monthly directional** | **46,550** | **50,850** | **55,450** | **44,400** | **48,450** | **53,880** | Medium |

One-time migration costs (separate from run-rate):
- Azure-first: **USD 1.8M–2.6M** over 9–12 months (platform build, migration factory, test hardening, phased cutover).
- GCP-first: **USD 2.0M–2.9M** over 10–13 months (higher IAM and messaging redesign overhead for this footprint).
- Confidence: Medium.

Unit economics applied: managed Kubernetes control plane, m5.xlarge-equivalent worker nodes, queue/topic operations at prod-level throughput, 50 GiB/env NFS file share, cross-region object replication, WAF/LB, and baseline Datadog ingestion at ~50 GB/day.

## 6. Migration Challenge Register

| Challenge | Impact | Likelihood | Mitigation | Owner role |
|---|---|---|---|---|
| SQS/SNS → Service Bus/Pub/Sub semantic gaps | High | High | Build messaging compatibility adapter + replay harness; run dual-publish burn-in before cutover | Platform Architect |
| IRSA/OIDC → Workload Identity redesign | High | High | Define target workload identity baseline early; codify in policy-as-code before first pilot cluster | Security Architect |
| KEDA SQS trigger → Service Bus/Pub/Sub trigger recalibration | Medium | High | Recalibrate scaler thresholds per engine using production queue-depth traces | SRE Lead |
| EFS latency vs. Azure Files NFS / Filestore | High | Medium | Run synthetic IO and application latency benchmarks; define pass/fail SLO before committing to target | App Performance Lead |
| WAF rule parity and custom exclusion mapping | Medium | Medium | Stage policy translation with canary ingress; monitor false-positive rate for ≥2 weeks | Network Security Lead |
| Velero DR workflow migration (cross-region S3 → Blob/GCS) | High | Medium | Rebuild backup/restore runbooks; conduct failover game days before production cutover | DR Lead |
| CI/CD and Spacelift → target stack orchestration | Medium | High | Introduce cloud-agnostic pipeline abstraction layer; maintain Spacelift for IaC apply across targets | DevOps Lead |
| Ops retraining (AKS/GKE, Service Bus, Key Vault) | Medium | High | 8–12 week enablement plan with shadow on-call rotations and SOP refresh | Platform Manager |

## 7. Migration Effort View

| Capability | Effort (S/M/L) | Risk (L/M/H) | Dependencies |
|---|---|---|---|
| Compute platform (EKS → AKS/GKE) | L | M | Cluster baseline, node pool policy, ingress controller selection, Karpenter/NAP decision |
| Messaging and async workflows | L | H | Contract tests, DLQ semantics, SNS filter-policy equivalents, KEDA trigger recalibration |
| Networking and edge | M | M | DNS cutover plan, WAF policy migration and burn-in, ingress class update |
| Data and storage (EFS, S3, Velero) | M | H | EFS → Azure Files/Filestore IO benchmark, backup bucket recreation, CMK redesign |
| Identity and security (IRSA → Workload Identity) | L | H | Largest policy surface; workload identity model, cross-account permission replacement |
| Observability (Datadog continuity) | M | M | Datadog agent reconfiguration for AKS/GKE, SLO remapping, alert tuning |
| CI/CD and IaC governance | M | M | Terraform/OpenTofu pipeline update, policy-as-code ports, release gate redefinition |

Migration difficulty rationale by capability:
- **Compute:** High difficulty — managed K8s parity exists on both targets, but Karpenter provisioning semantics, Bottlerocket OS specifics, and IRSA bindings all require careful re-expression.
- **Networking:** Medium — services are broadly comparable; DNS cutover sequencing and WAF rule fidelity are the main scheduling risks.
- **Data:** High — EFS throughput/latency behaviour on Azure Files NFS must be validated before committing; DR topology requires full rebuild.
- **Messaging:** High — SQS/SNS semantics, filter policies, and KEDA trigger configurations are tightly coupled and require parallel-run validation.
- **Identity/Security:** High — largest redesign surface; cross-account SNS policies and IRSA role chaining must be fully re-mapped.
- **Observability:** Medium — Datadog continuity significantly reduces risk; agent reconfiguration and SLO remapping are the main tasks.
- **Storage/Backup:** High — cross-region Velero bucket strategy and CMK key hierarchy require full rebuild and game-day validation.

## 8. Decision Scenarios

**Cost-first scenario**
- Primary target: **GCP**
- Why: Lower directional monthly run-rate across US, EU, and AU for this workload profile (~4–5% lower vs Azure).
- Tradeoff: Higher migration complexity for current IRSA-heavy identity model and SNS filter-policy patterns.

**Speed-first scenario**
- Primary target: **Azure**
- Why: Faster enterprise migration execution due to strong AKS managed-service parity with EKS, Service Bus feature alignment with SQS/SNS, and lower organisational friction in a Microsoft-first enterprise.
- Tradeoff: Slightly higher directional run-rate vs GCP in most regions.

**Risk-first scenario**
- Primary target: **Azure with phased dual-run**
- Why: Preserve queue-driven architecture patterns by using Service Bus (closest semantic match to SQS/SNS), retain Datadog continuity, and maintain AWS production until each wave passes DR game day.
- Tradeoff: Temporary dual-cloud egress spend and a longer transition window (~14–18 months total).

## 9. Recommended Plan (30/60/90)

**30 days — Decisions and benchmarks**
- Freeze Architecture Decision Records (ADRs) for: workload identity model, messaging platform target, EFS replacement strategy, DR regional topology.
- Build Azure and GCP landing zones for both US and EU.
- Implement migration test harness covering async request/reply workflows, queue-depth autoscaling, and latency SLO probes.
- Benchmark Azure Files NFS and Google Filestore against EFS for engine workloads.

**60 days — Pilot migration**
- Stand up pilot AKS cluster (Azure) and GKE cluster (GCP) with representative engine workload.
- Migrate one non-critical engine path end-to-end: queue triggers, ingress, IRSA replacement, observability.
- Complete DR drill against target architecture — validate RTO ≤4h and RPO ≤30m.
- Select final target platform based on measured latency and operating effort.

**90 days — Wave 1 production**
- Execute wave-1 production migration for sandbox and dev environments on the selected platform (recommended: Azure).
- Establish production readiness gates: availability SLO, rollback criteria, DLQ alerting, key rotation validation.
- Define wave-2 scope (staging → prod) and obtain architecture sign-off.

**Required architecture decisions before execution:**
1. Final workload identity pattern (AKS Workload Identity vs. GKE Workload Identity).
2. Messaging abstraction contract — Service Bus vs. Pub/Sub, DLQ and retry model.
3. File storage platform and IO SLO pass/fail criteria before wave-1 commit.
4. Regional topology: active-passive vs. active-active per region pair.
5. IaC toolchain continuity: Spacelift + OpenTofu retained or replaced.

## 10. Open Questions

- What is the peak message-per-second throughput and maximum acceptable backlog depth per engine queue?
- Are there hard contractual data-residency boundaries per tenant beyond US/EU/AU (e.g. specific country-level)?
- Is active-active multi-region required for any environment, or is warm-standby DR sufficient?
- Which engine queues, if any, require strict FIFO ordering guarantees?
- What is the maximum acceptable cutover window per production environment?
- Should Datadog remain the single observability pane post-migration, or is a native-cloud monitor transition planned?
- Are HxPR/HxPS cross-account SNS publish permissions being migrated simultaneously or decoupled?

## 11. Component Diagrams

Draw.io artifact:
- [Reports/multi-cloud-migration-diagrams-20260414-173000-utc.drawio](multi-cloud-migration-diagrams-20260414-173000-utc.drawio)

SVG exports (one per architecture view):
- AWS Source: [Reports/multi-cloud-migration-diagrams-20260414-173000-utc-aws-source.svg](multi-cloud-migration-diagrams-20260414-173000-utc-aws-source.svg)
- Azure Target: [Reports/multi-cloud-migration-diagrams-20260414-173000-utc-azure-target.svg](multi-cloud-migration-diagrams-20260414-173000-utc-azure-target.svg)
- GCP Target: [Reports/multi-cloud-migration-diagrams-20260414-173000-utc-gcp-target.svg](multi-cloud-migration-diagrams-20260414-173000-utc-gcp-target.svg)

Page mapping (draw.io):
- **AWS Source** — current-state AWS component architecture (EKS, SNS/SQS, ALB/WAF/Route53, EFS, S3, Datadog).
- **Azure Target** — recommended Azure target architecture (AKS, Service Bus, App Gateway/WAF/Azure DNS, Azure Files, Blob, Azure Monitor).
- **GCP Target** — alternative GCP target architecture (GKE, Pub/Sub, HTTPS LB/Cloud Armor/Cloud DNS, Filestore, GCS, Cloud Operations).

Note: Mermaid blocks are intentionally not embedded in this report. All diagram content is provided as editable draw.io XML and rendered SVG files in the Reports folder.
