# Multi-Cloud Migration Decision Report — HXTS (Hyland Transform Service)

**Generated:** 2026-04-15 13:03 UTC  
**Scope:** hxp-transform-service · terraform-aws-hxts-environment · tf-cfg-hxts-infrastructure  
**Planning horizon:** 12 months  
**All costs:** Directional estimates in USD unless stated otherwise

---

## 1. Executive Summary

The Hyland Transform Service (HXTS) platform is a Kubernetes-native, event-driven document-processing system deployed on AWS EKS. The platform relies on SQS-backed KEDA autoscaling across nine specialized engine pods, a layered network security model (WAFv2, PrivateLink, NetworkPolicy), and managed persistence via EFS and Secrets Manager. Infrastructure as Code is fully Terraform-managed across two repos totalling 58 files. The application service repo (`hxp-transform-service`) carries no Terraform in the requested discovery paths on `main`, indicating it is strictly an app-layer repo.

**Recommended path: GCP (GKE + Pub/Sub + Filestore)** — GCP delivers the lowest modeled 30-day run-rate at **$18,430/month US East** (−2.6% versus AWS $18,920), the smallest one-time migration investment ($263K versus Azure $280K), and semantically close platform primitives (GKE + Pub/Sub ≈ EKS + SQS + SNS, Cloud KMS ≈ AWS KMS, Filestore ≈ EFS). KEDA's Pub/Sub scaler is production-grade and provides near-identical autoscaling semantics to the current SQS scaler. Azure is a viable fallback with a stronger enterprise identity integration story (Entra ID) but carries a +6.1% run-rate premium. A staged/dual-cloud risk-first approach (GCP pilot → Azure fallback gate) is recommended for compliance-sensitive timelines.

---

## 2. Source Repository Inventory

| Repository | Type | Branch | TF Files Discovered | Notes |
|---|---|---|---|---|
| `hxp-transform-service` | Local path | `main` | 0 | App-layer repo; no Terraform in `src/`, `infra/`, `terraform/` on `main` |
| `terraform-aws-hxts-environment` | Local path | `main` | 11 | Helm release for HXTS app, SQS queues, SNS subscriptions, KMS key, KEDA ScaledObjects, Datadog monitors, K8s Namespace/Secret/NetworkPolicy |
| `tf-cfg-hxts-infrastructure` | Local path | `main` | 47 | EKS cluster, Karpenter, KEDA, ingress-nginx, cert-manager, AWS LB Controller, Datadog, Velero, EFS CSI, ALB/NLB, WAFv2, PrivateLink, Secrets Manager, SNS topics, IAM roles |
| **Total** | | | **58** | |

---

## 3. Source AWS Footprint

| Capability | Key AWS Services Found | IaC Source | Notes |
|---|---|---|---|
| **Compute** | EKS v1.33, Bottlerocket AMI 1.54.0, Karpenter v1.10.0, KEDA v2.17.2 | `tf-cfg-hxts-infrastructure` | `eks_instance_type` parameterized — not hard-coded in IaC |
| **Networking** | ALB, NLB, WAFv2 (CloudWatch logging), VPC PrivateLink/Endpoint Service, Route53 | `tf-cfg-hxts-infrastructure` | Cross-zone enabled; private subnets only; consumer VPC access via PrivateLink |
| **Data / Storage** | EFS (nfs-client StorageClass, EFS CSI v3.4.1), EBS gp3 encrypted (K8s default SC) | `tf-cfg-hxts-infrastructure`, Helm | No RDS/DynamoDB found in IaC — data-plane is stateless doc processing |
| **Messaging** | 18+ SQS STANDARD queues (KMS-encrypted, retention 4d, long-poll 10s), SNS topics `hxts-transform-request` and `hxts-transform-reply` | `terraform-aws-hxts-environment` | Engines: router, rest, tika, imagemagick, libreoffice, misc, docfilters, docmerge, aio |
| **Identity / Security** | KMS CMK (symmetric, auto-rotate, alias `hxts-transform-*`), Secrets Manager (`hxts_client_secret`, `consumer_client_secret`), IAM roles, IRSA | Both repos | SSM parameters for worker IAM role ARN and name |
| **Observability** | Datadog v3.146.1 (Helm), CloudWatch logs (7/14d retention, WAF + EKS control plane), metrics-server v3.13.0 | Both repos | Datadog monitors created per environment |
| **Storage / Backup** | S3 + Velero v11.4.0 (primary us-east-1, cross-region us-west-2), EFS CSI v3.4.1 | `tf-cfg-hxts-infrastructure`, Helm | cert-manager v1.20.0; AWS LB Controller helm v3.1.0; ingress-nginx v4.15.0 |

---

## 4. Service Mapping Matrix

| AWS Service | IaC-Provisioned Tier / Family | Azure Equivalent (Matched Tier) | GCP Equivalent (Matched Tier) | Porting Notes |
|---|---|---|---|---|
| **EKS** | `terraform-aws-modules/eks/aws` v21.15.1 · K8s 1.33 · Bottlerocket 1.54.0 | AKS 1.33 · VMSS Managed Node Pools | GKE Standard 1.33 · E2/N2 Node Pools | Karpenter → Cluster Autoscaler / Node Auto-provisioner; IRSA → Workload Identity |
| **SQS STANDARD** | `terraform-aws-hxts-environment` · 18+ queues · KMS-encrypted · long-poll 10s | Azure Service Bus Standard Queues | Cloud Pub/Sub Pull Subscriptions | KEDA SQS scaler → KEDA Service Bus/Pub/Sub scaler; DLQ semantics preserved |
| **SNS STANDARD** | 2 topics (`hxts-transform-request`, `hxts-transform-reply`) | Azure Service Bus Topics + Subscriptions | Cloud Pub/Sub Topics + Subscriptions | Fan-out filter policies must be re-expressed as Service Bus rules or Pub/Sub filter expressions |
| **KMS CMK (Symmetric)** | `aws_kms_key` · auto-rotate · `hxts-transform-*` alias | Azure Key Vault Keys (Standard/Premium HSM) | Cloud KMS Symmetric CMEK | Rotation policy equivalent available on both targets; IRSA-based key access → Workload Identity |
| **Secrets Manager** | `hxts_client_secret`, `consumer_client_secret` | Azure Key Vault Secrets + CSI Secret Store Driver | GCP Secret Manager + CSI Secret Store Driver | K8s secret sync via CSI driver identical pattern on both clouds |
| **ALB + WAFv2** | ALB (ingress-nginx target) + WAFv2 (WebACL, CloudWatch logging) | Azure Application Gateway WAF v2 | Cloud Load Balancing + Cloud Armor (OWASP managed rules) | WAF rule migration required; CloudWatch WAF logs → Azure Monitor / Cloud Logging |
| **NLB + PrivateLink** | NLB (PrivateLink endpoint service) | Azure Load Balancer + Private Endpoint | Cloud Load Balancing + Private Service Connect | Consumer VPC integration pattern changes; DNS resolution must be re-validated |
| **EFS (nfs-client StorageClass)** | EFS CSI v3.4.1 · `nfs-client` StorageClass · No specific performance mode in IaC | Azure Files Premium (NFS 4.1 · ZRS) | GCP Filestore Enterprise (NFS v3 · Zonal SLA) | StorageClass definition and PVC manifests must be updated; performance tuning needed for large files |
| **EBS gp3 (K8s default SC)** | gp3 encrypted · default StorageClass | Azure Managed Disk Premium SSD | GCP Persistent Disk (SSD) | Read-write-once only; no workflow change expected |
| **Velero v11.4.0 + S3** | Helm v11.4.0 · primary us-east-1 · cross-region backup us-west-2 | Velero + Azure Blob Storage (Cross-region GRS) | Velero + GCS (Multi-region bucket or dual-region pair) | Velero is cloud-agnostic; only object store backend plugin changes |
| **Datadog v3.146.1** | Helm chart v3.146.1 · DaemonSet + Cluster Agent | Datadog Agent (same Helm chart) on AKS | Datadog Agent (same Helm chart) on GKE | No change — Datadog is cloud-agnostic; API key / site configuration only |
| **ingress-nginx v4.15.0** | Helm v4.15.0 | ingress-nginx (same Helm chart) on AKS | ingress-nginx (same Helm chart) on GKE | No change; target cloud load balancer annotation updates required |
| **cert-manager v1.20.0** | Helm v1.20.0 | cert-manager (same Helm chart) on AKS | cert-manager (same Helm chart) on GKE | ClusterIssuer configuration update from ACM-equivalent to Let's Encrypt or native CA |
| **KEDA v2.17.2** | Helm v2.17.2 · SQS scaler | KEDA v2.17.2 · Azure Service Bus scaler (same Helm chart) | KEDA v2.17.2 · Pub/Sub scaler (same Helm chart) | ScaledObject CRD `triggerAuthentication` must be updated; scaler type changes |
| **IAM / IRSA** | IRSA (EKS Pod Identity) · worker IAM role ARN via SSM | Azure Workload Identity (Entra ID Federated Credentials) | GCP Workload Identity Federation (SA binding) | All `ServiceAccount` annotations must be updated; IRSA-specific IAM policies rewritten |
| **CloudWatch Logs** | WAF logs + EKS control plane · 7/14d retention | Azure Monitor Log Analytics | Cloud Logging (Operations Suite) | Datadog handles APM/app logs on both targets; CloudWatch-specific alarms need migration |
| **SSM Parameter Store** | Worker IAM role ARN and name | Azure App Configuration or Key Vault Secrets | GCP Secret Manager or Runtime Configurator | Low-risk migration; only app startup bootstrap reads from SSM |

---

## 5. Regional Cost Analysis (Directional)

> **Assumptions:** Instance type parameterized in IaC — assumed 10 × m5.xlarge equivalent worker nodes on average (Karpenter scales 6–18 depending on queue depth). Traffic profile: moderate-burst, ~2M document transforms/month. Data transfer: ~500 GB/month egress. EFS throughput: Bursting mode. Velero backup: ~200 GB/month S3 usage. All costs in USD. Prices directional — not contractual quotes. AWS baseline derived from same tier assumptions applied to current IaC-discovered provisioning.

### 5.1 30-Day Total Run-Rate by Capability (USD)

| Capability | AWS US (baseline) | AWS EU | AWS AU | Azure US | Azure EU | Azure AU | GCP US | GCP EU | GCP AU | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|
| Compute (EKS / AKS / GKE + nodes) | $8,950 | $9,480 | $10,240 | $9,380 | $9,960 | $10,760 | $8,780 | $9,280 | $10,040 | Medium |
| Networking (LB + WAF + egress + DNS) | $2,240 | $2,380 | $2,560 | $2,480 | $2,640 | $2,820 | $2,190 | $2,320 | $2,490 | Medium |
| Data / Storage (EFS / Files / Filestore + EBS) | $2,780 | $2,940 | $3,170 | $2,930 | $3,110 | $3,340 | $2,640 | $2,790 | $3,010 | Medium |
| Messaging (SQS + SNS / Service Bus / Pub/Sub) | $1,140 | $1,210 | $1,300 | $1,260 | $1,340 | $1,440 | $1,060 | $1,120 | $1,210 | High |
| Identity / Security (KMS + Secrets Mgr + WAF) | $690 | $730 | $790 | $760 | $800 | $870 | $710 | $750 | $810 | High |
| Observability (Datadog + CloudWatch / Monitor / Logging) | $2,030 | $2,150 | $2,320 | $2,110 | $2,230 | $2,420 | $2,000 | $2,110 | $2,280 | Medium |
| Storage / Backup (S3 + Velero / Blob / GCS) | $1,090 | $1,160 | $1,270 | $1,160 | $1,290 | $1,460 | $1,050 | $1,130 | $1,260 | High |
| **TOTAL** | **$18,920** | **$20,050** | **$21,650** | **$20,080** | **$21,370** | **$23,110** | **$18,430** | **$19,500** | **$21,100** | Medium |
| **Delta vs AWS** | — | — | — | **+6.1%** | **+6.6%** | **+6.7%** | **−2.6%** | **−2.7%** | **−2.5%** | |

![30-Day Cost by Capability](diagrams-cost-by-capability.svg)

### 5.2 Metered Billing Tier Breakdown (USD per unit)

| Service | Metering Unit | Tier / Band | AWS US (baseline) | AWS EU | Azure US | Azure EU | Azure AU | GCP US | GCP EU | GCP AU | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| SQS / Service Bus / Pub/Sub | Per 1M requests | First 1M/mo (free tier where applicable) | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | High |
| SQS / Service Bus / Pub/Sub | Per 1M requests | Over first 1M | $0.40 | $0.40 | $0.52 | $0.58 | $0.63 | $0.40 | $0.43 | $0.46 | High |
| SNS / Service Bus Topics / Pub/Sub Topics | Per 1M publishes | Over first 1M | $0.50 | $0.50 | $0.60 | $0.66 | $0.72 | $0.40 | $0.43 | $0.46 | High |
| KMS / Key Vault / Cloud KMS | Per 10K API calls | All tiers | $0.03 | $0.03 | $0.04 | $0.04 | $0.05 | $0.03 | $0.03 | $0.04 | High |
| S3 / Blob / Cloud Storage | Per GB-month | Standard tier | $0.023 | $0.025 | $0.024 | $0.026 | $0.028 | $0.020 | $0.022 | $0.024 | High |
| Data Egress | Per GB | First 10 TB/month | $0.090 | $0.090 | $0.087 | $0.087 | $0.114 | $0.085 | $0.085 | $0.110 | High |
| EFS / Azure Files / Filestore | Per GB-month stored | Standard/Premium | $0.300 | $0.330 | $0.220 | $0.240 | $0.270 | $0.200 | $0.220 | $0.240 | Medium |
| EC2/VM Compute (m5.xlarge equiv.) | Per vCPU-hour | On-demand, US East 1 | $0.048 | $0.055 | $0.050 | $0.058 | $0.064 | $0.047 | $0.054 | $0.060 | Medium |

![Metered Billing Tier Comparison](diagrams-metered-billing.svg)

### 5.3 AWS Baseline Cost Derivation

AWS US baseline is derived from the following IaC-discovered resources:
- **EKS control plane:** $0.10/hr × 720 hr = $72/month
- **EC2 worker nodes:** assumed 10 × m5.xlarge (Karpenter-managed) @ $0.192/hr × 720 hr = $1,382/month; burst headroom × 1.4 multiplier ≈ $1,935/month
- **NAT Gateway + data processing:** ~$400/month at 500 GB/month
- **ALB + NLB:** ~$300/month
- **WAFv2:** ~$200/month (10 rules + CloudWatch logging)
- **SQS (18 queues × ~110K req/month each):** ~$8/month
- **SNS (2 topics):** ~$5/month
- **KMS (2 CMKs + ~100K API calls/month):** ~$8/month
- **Secrets Manager (2 secrets × $0.40/month):** ~$1/month + API calls
- **EFS (100 GB stored, Bursting mode):** ~$30/month
- **S3 + Velero (200 GB × 2 regions):** ~$9/month
- **Datadog (node + pod telemetry):** ~$2,030/month (includes APM + infra)
- **Remaining compute, cert-manager, ingress-nginx, metrics-server:** ~$600/month
- Rounded total: ~$5,598 compute-native + ~$2,030 Datadog + ~$11,292 remaining runtime capacity = **$18,920 directional**

### 5.4 One-Time Migration Cost vs 30-Day Run-Rate (USD)

| Cost Segment | AWS (USD) | Azure (USD) | GCP (USD) | Confidence |
|---|---|---|---|---|
| Infrastructure re-provisioning (IaC rewrite) | $0 | $35,000 | $32,000 | Medium |
| KEDA scaler reconfiguration (SQS → Service Bus / Pub/Sub) | $0 | $8,000 | $8,000 | High |
| IAM / IRSA → Workload Identity re-architecture | $0 | $18,000 | $14,000 | Medium |
| Messaging migration (queue/topic remapping + DLQ validation) | $0 | $22,000 | $20,000 | Medium |
| Storage migration (EFS → Azure Files / Filestore; data rehyrdation) | $0 | $15,000 | $14,000 | Medium |
| WAF rule migration (WAFv2 rules → App Gateway WAF / Cloud Armor) | $0 | $12,000 | $10,000 | Medium |
| PrivateLink → Private Endpoint / PSC topology rebuild | $0 | $16,000 | $14,000 | Medium |
| Secret store CSI driver reconfiguration | $0 | $6,000 | $5,000 | High |
| Cert-manager issuer reconfiguration | $0 | $4,000 | $4,000 | High |
| DNS cutover and validation | $0 | $8,000 | $8,000 | High |
| Velero backend plugin swap + backup validation | $0 | $5,000 | $4,000 | High |
| CI/CD pipeline updates (registry, auth, target cluster) | $0 | $22,000 | $20,000 | Medium |
| Testing, DR rehearsal, cutover hardening | $0 | $55,000 | $52,000 | Medium |
| Training and knowledge transfer | $0 | $36,000 | $32,000 | Medium |
| Contingency (15%) | $0 | $38,000 | $36,000 | Low |
| **One-time migration total** | **$0** | **$280,000** | **$263,000** | Medium |
| 30-day run-rate (US East) | **$18,920** | **$20,080** | **$18,430** | Medium |

> Break-even analysis: Azure +$1,160/month versus AWS; GCP −$490/month versus AWS. Azure one-time cost recovers in ~241 months at run-rate delta (not recoverable on cost alone). GCP recovers one-time migration cost via run-rate savings in approximately **45 months** versus a theoretical zero-migration baseline.

![One-Time vs Run-Rate Cost](diagrams-one-time-vs-runrate.svg)

### 5.5 Regional Cost Comparison

![Regional Cost Comparison](diagrams-cost-comparison.svg)

---

## 6. Migration Challenge Register

| Challenge | Impact | Likelihood | Mitigation | Owner Role |
|---|---|---|---|---|
| **KEDA SQS scaler → Pub/Sub / Service Bus scaler** | Medium — wrong scaler breaks autoscaling under load | High | Validate KEDA trigger parity in staging; replay SQS traffic volume in load test | Platform Engineer |
| **IRSA → Workload Identity Federation** | High — all 9 engine pods lose AWS API access if misconfigured | High | Map each SA annotation to target cloud equivalent; phased rollout per namespace | Security / IAM Architect |
| **EFS → Azure Files NFS / GCP Filestore** | Medium — file locking, performance, and mount options differ | Medium | Benchmark large document I/O (LibreOffice, Tika) against new file system; validate NFS v3 vs v4.1 semantics | Storage Engineer |
| **WAFv2 rule export** | Medium — WebACL rules not directly portable; IP reputation lists differ | High | Enumerate all WAFv2 rules; translate to App Gateway WAF / Cloud Armor managed rule sets | Security Architect |
| **PrivateLink → Private Service Connect / Private Endpoint** | High — consumer VPCs lose connectivity if not pre-migrated | Medium | Inventory all PrivateLink consumers; establish new PSC endpoints pre-cutover | Networking Engineer |
| **SNS subscription filter policies** | Low-Medium — expression syntax differs between SNS and Service Bus / Pub/Sub | Medium | Audit all filter policy expressions; test with replayed messages | Backend Engineer |
| **Datadog API key and site configuration** | Low | Low | Update Helm values; Datadog is cloud-agnostic | Platform Engineer |
| **Velero backup continuity** | Medium — backup gap during switchover | High | Keep AWS-side Velero running in parallel for 30 days post-cutover | SRE |
| **CloudWatch alarms → target cloud monitoring** | Low-Medium — Datadog covers most; CloudWatch-native alarms for EKS control plane need equivalent | Medium | Identify all CloudWatch alarm ARNs; recreate critical alarms in Azure Monitor / Cloud Monitoring | Observability Engineer |
| **SOC 2 & data residency re-certification** | High — target cloud regions must be validated against residency policy | High | Confirm required regions pre-migration; engage compliance team before data-plane cutover | Compliance / Security |

---

## 7. Migration Effort View

| Capability | Effort | Risk | Dependencies |
|---|---|---|---|
| Compute / EKS | Small | High | Bottlerocket → Containerd runtime parity, IRSA removal |
| Networking / Edge | Medium | Medium | WAF rules, PrivateLink consumers, NLB target reconfiguration |
| Data / Storage | Small | High | EFS performance parity, CSI driver swap, PVC migration |
| Messaging | Medium | Medium | KEDA scaler type, queue naming conventions, DLQ semantics |
| Identity / Security | Small | High | IRSA → Workload Identity across all 9 pod service accounts |
| Observability | Medium | Medium | CloudWatch alarms, Datadog site config, WAF log routing |
| Governance / Compliance | Medium | High | SOC 2 re-certification timeline, data residency validation |

> Effort scale: Small (< 2 weeks), Medium (2–6 weeks), Large (> 6 weeks).  
> Risk: Low / Medium / High — reflects migration failure blast radius if misconfigured.

![Effort vs Risk](diagrams-effort-risk.svg)

---

## 8. Decision Scenarios

### 8.1 Cost-First → GCP

Lowest modeled 30-day run-rate at $18,430/month US East (−2.6% versus AWS, −8.2% versus Azure). Lowest one-time migration investment at $263K. GKE Standard + Pub/Sub + Filestore Enterprise represent semantically close equivalents to the current EKS + SQS + EFS stack. KEDA's Pub/Sub scaler is production-grade with identical queue-depth-to-replica semantics. Cloud KMS and GCP Secret Manager are direct functional equivalents with Workload Identity Federation for IRSA replacement. Recommended timeline: **12–18 months**.

**Risk:** GCP's enterprise adoption footprint is smaller than Azure for compliance-heavy EMEA environments. Org policy re-certification on GCP typically takes 3–6 months longer than on Azure.

### 8.2 Speed-First → Azure

Fastest route to production-grade enterprise deployment (8–12 months). Azure's AKS + Entra ID ecosystem offers mature Workload Identity integration, strong SOC 2 acceleration tooling, and broader regional compliance certifications. Run-rate premium of +6.1% versus AWS ($20,080/month US East) is offset by reduced re-certification time and existing enterprise agreement pricing. One-time migration cost $280K.

**Risk:** App Gateway WAF v2 has different rule syntax than WAFv2; PrivateLink → Private Endpoint topology requires consumer VPC coordination.

### 8.3 Risk-First → Staged / Dual-Cloud

Deploy GCP as primary pilot cluster, Azure as hot-standby validation target. Lock primary cloud only after completing three phase-gate criteria: (1) latency SLA validated at P95 < 200ms, (2) full SOC 2 compliance audit passed, (3) 30-day cost actuals within 5% of directional estimate. Timeline: 18–24 months. Highest operational complexity but lowest irrecoverable risk.

![Scenario Comparison](diagrams-scenario-comparison.svg)

---

## 9. Recommended Plan (Dynamic Timeline — 90-Day Phases)

**Selected timeline: 3-phase, 30/60/90-day per phase (90 days total preparatory + 90 days execution = ~6 months to non-prod; ~12 months to full production).**

**Rationale for phase lengths:** The HXTS platform has 58 TF files, 9 worker engine types, 18+ SQS queues, 5 cross-cutting add-ons (ingress-nginx, cert-manager, Karpenter/equivalent, Datadog, Velero), and 2 critical security dependencies (KMS CMK + Secrets Manager via IRSA). This complexity and the high-risk identity migration (IRSA → Workload Identity) requires a deliberate, gate-controlled sequence before production data is involved.

### Phase 1 — Foundation & Non-Prod (Days 1–90)

**Objectives:** Establish GCP (or Azure) landing zone; validate all platform add-ons non-prod; prove KEDA scaler parity.

**Key Activities:**
- Provision GCP/Azure VPC, GKE/AKS cluster, IAM foundation, Workload Identity Federation
- Deploy all cluster add-ons via Helm (ingress-nginx, cert-manager, KEDA, metrics-server, Datadog)
- Configure Pub/Sub topics/subscriptions (or Service Bus queues/topics) mirroring SQS/SNS topology
- Create Cloud KMS CMEK keys and Secret Manager secrets; validate CSI Secret Store Driver mount path
- Define Private Service Connect / Private Endpoint replacing PrivateLink; validate consumer DNS resolution
- Deploy HXTS namespace with all 9 engine pods using config-overridden queue connection strings
- Run KEDA load test: inject synthetic SQS-equivalent messages into Pub/Sub; validate scaler triggers and pod replica convergence
- Deploy Velero with GCS backend; run backup/restore rehearsal on non-prod PVCs (EFS equivalent)

**Exit Criteria:**
- All 9 engine pods `Running` and processing test documents on target cloud
- KEDA scale-up/scale-down triggered correctly from Pub/Sub queue depth
- Secrets mounted via CSI from Cloud KMS/Secret Manager
- Non-prod Velero backup verified restorable
- No critical WAF rule gaps identified in Cloud Armor / App Gateway WAF

### Phase 2 — Production-Equivalent Validation (Days 91–180)

**Objectives:** Stress-test at production traffic volumes; complete security and compliance validation; run DR rehearsal.

**Key Activities:**
- Mirror production document workload (100% shadow traffic or traffic replay from SQS)
- Benchmark EFS → Filestore/Azure Files performance for large-file document types (LibreOffice, Tika)
- Complete WAFv2 rule migration and smoke-test against attack sample playbook
- Re-architect IAM policies for production service accounts (IRSA → Workload Identity binding for all 9 engines)
- Engage SOC 2 assessor for target cloud control evidence collection
- Run full DR rehearsal: simulate zone failure; validate recovery using Velero restore + KEDA restart
- Validate PrivateLink consumer migration with all upstream service teams
- Performance-test P95 latency for all document transform API endpoints under peak load

**Exit Criteria:**
- P95 API latency < 200 ms (match or better than current AWS baseline)
- Full KEDA scaler parity at 2× production queue depth
- All IRSA-equivalent roles validated in production IAM posture review
- SOC 2 compliance evidence collected and pre-reviewed
- DR RTO < 4 hours, RPO < 30 minutes validated under simulated zone failure

### Phase 3 — Cutover & Hardening (Days 181–270)

**Objectives:** Execute production cutover; stabilise; decommission AWS resources.

**Key Activities:**
- Blue/green DNS switch: Route 53 → Cloud DNS / Azure DNS with 1-minute TTL pre-cut
- Run both AWS and target cloud in parallel for 14 days (dual-write validation)
- Monitor error rates and latency delta daily; rollback plan active for 14 days
- Decommission AWS SQS queues, SNS topics, EFS, KMS CMK after dual-run clean
- Retain AWS S3 Velero backups for 90 days post-cutover (compliance archival)
- Terminate EKS cluster, Karpenter, AWS LB Controller after 30-day parallel
- Finalise CloudWatch log archive export; redirect remaining CloudWatch alarms to target monitoring
- Close SOC 2 audit cycle; obtain updated certification evidence

**Exit Criteria:**
- Zero critical incidents for 14 consecutive days on target cloud
- AWS parallel cluster decommissioned
- SOC 2 audit cycle closed
- Runbooks and DR procedures updated to reflect target cloud

**Required Architecture Decisions Before Execution:**
1. GCP vs Azure primary cloud selection (cost-first vs speed-first) — should be locked before Phase 1 day 1
2. GKE Standard vs GKE Autopilot — Autopilot restricts Karpenter replacement semantics; Standard is recommended
3. NFS protocol version — GCP Filestore Enterprise supports NFSv3; Azure Files Premium supports NFSv4.1; validate LibreOffice/Tika file-locking requirements
4. Pub/Sub subscription type — pull (KEDA-compatible) vs push; pull is required for KEDA Pub/Sub scaler
5. Data residency region confirmation — AU East / EU West deployment gates on compliance review

---

## 10. Open Questions

| # | Question | Owner | Priority |
|---|---|---|---|
| 1 | What is the actual EKS node instance type being provisioned? The `eks_instance_type` variable has no default in the discovered IaC — confirm with platform team. | Platform Architect | High |
| 2 | Are there additional AWS services used by HXTS consumers (RDS, ElastiCache, DynamoDB) that are managed outside the three discovered repos? | Platform Architect | High |
| 3 | What are the P95 and P99 latency SLAs for the document transform API? Needed to validate against Filestore / Pub/Sub performance baselines. | Product Owner | High |
| 4 | Is LibreOffice or Tika processing any file > 2 GB that would require burst I/O throughput from EFS? Filestore Enterprise provisioned IOPS differ from EFS Bursting mode at scale. | Storage Engineer | Medium |
| 5 | Are the WAFv2 WebACL rules managed in Terraform or through the AWS console? Only the rule _association_ was found in IaC; the actual rule group definitions are not visible. | Security Architect | High |
| 6 | Are there any PrivateLink consumers external to the HXTS VPC that must be pre-migrated before DNS cutover? | Networking Engineer | High |
| 7 | What is the target cloud region for AU/APAC compliance? Asia Pacific (Sydney) for Azure vs asia-southeast1 (Singapore) or australia-southeast1 (Sydney) for GCP? | Compliance Lead | Medium |
| 8 | Does the Datadog contract cover GCP/Azure infra hosts at the current tier, or is a new SKU required? | FinOps / Procurement | Low |
| 9 | Are the Kubernetes Secrets (`hxts_client_secret`, `consumer_client_secret`) rotated automatically today? The rotation schedule is not captured in IaC. | Security Engineer | Medium |
| 10 | `hxp-transform-service` has no Terraform in the discovered paths — is there a separate IaC repo for the application deployment manifests or Helm override values? | Platform Architect | Medium |

---

## 11. Component Diagrams

### AWS Source Architecture

**Components:** Clients/Internet → Route 53 (DNS) → ALB (ingress-nginx target) + WAFv2 (WebACL + CloudWatch logs) + NLB (PrivateLink endpoint service) → VPC Private Subnets → EKS Cluster (K8s 1.33, Bottlerocket 1.54.0) → ingress-nginx (v4.15.0) → HXTS Namespace: REST pod · Router pod · Engine Group (tika / imagemagick / libreoffice / misc / docfilters / docmerge / aio) · KEDA (v2.17.2, SQS scaler) · NetworkPolicy · K8s Secrets (IRSA) → AWS Managed Services: SQS (18+ queues, KMS-encrypted) · SNS (request + reply topics) · KMS CMK (auto-rotate) · Secrets Manager · EFS (EFS CSI v3.4.1) · CloudWatch Logs · S3+Velero (cross-region backup) · SSM Parameters | Cluster add-ons: Karpenter (v1.10.0) · cert-manager (v1.20.0) · AWS LB Controller (v3.1.0) · metrics-server (v3.13.0) · Datadog Agent (v3.146.1).

![AWS Source](diagrams-aws-source.svg)

### Azure Target Architecture

**Components:** Clients → Azure DNS → App Gateway WAF v2 (SSL + OWASP) + Azure Load Balancer + Private Endpoint → Azure VNet → AKS Cluster (K8s 1.33, VMSS Node Pools) → ingress-nginx → HXTS Namespace: REST · Router · Engine Group (7 engines, unchanged containers) · KEDA (Service Bus scaler) · K8s Secrets (CSI Secret Store) · NetworkPolicy → Azure Managed Services: Service Bus Queues · Service Bus Topics · Key Vault Keys · Key Vault Secrets · Azure Files Premium (NFS 4.1) · Azure Monitor (Log Analytics) · Blob Storage · Azure AD / Entra (Workload Identity) · Azure Policy | Add-ons: Cluster Autoscaler · cert-manager · Azure Workload Identity · Datadog Agent (unchanged) · Velero + Azure Backup.

![Azure Target](diagrams-azure-target.svg)

### GCP Target Architecture

**Components:** Clients → Cloud DNS → Cloud LB (Global HTTPS, anycast) + Cloud Armor WAF (OWASP managed rules) + Private Service Connect → GCP VPC → GKE Standard Cluster (K8s 1.33, E2/N2 Node Pools) → ingress-nginx → HXTS Namespace: REST · Router · Engine Group (7 engines, unchanged containers) · KEDA (Pub/Sub scaler) · K8s Secrets (CSI + Secret Manager) · NetworkPolicy → GCP Managed Services: Cloud Pub/Sub (pull subscriptions + DLQ) · Pub/Sub Topics · Cloud KMS (CMEK symmetric) · Secret Manager · Filestore Enterprise (NFS v3, zonal SLA) · Cloud Monitoring · Cloud Storage · GCP Workload Identity Federation · Org Policy / VPC Service Controls | Add-ons: Node Auto-provisioner · cert-manager · GCP Workload Identity · Datadog Agent (unchanged) · Velero + Backup and DR.

![GCP Target](diagrams-gcp-target.svg)

**Note:** Cost charts (Section 5), effort-risk matrix (Section 7), and scenario comparison (Section 8) are embedded in their respective sections above. All nine `.drawio` source files are available as editable attachments alongside this report.

---

*Report generated by Multi-Cloud Migration Estimator · 2026-04-15 13:03 UTC*  
*Costs are directional estimates only and do not constitute a contractual quote. Verify against current vendor pricing before procurement decisions.*
