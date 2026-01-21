# EKS with Karpenter

Minimal, production-ready Terraform setup for **Amazon EKS** with **Karpenter**.
Designed around a **fixed on-demand baseline** and **elastic Spot capacity**, with
**ARM64 (Graviton) preferred** and **AMD64 supported**.

---

## What this creates

- VPC (3 AZs)
- EKS cluster
- Baseline **managed node group** (on‑demand, fixed size)
- Karpenter (installed via Helm)
- Karpenter CRDs (separate chart, upgrade-safe)
- Spot NodePools:
  - ARM64 (Graviton) – preferred
  - AMD64 – fallback
- IAM + Pod Identity
- Spot interruption handling (SQS + EventBridge)

Terraform manages infrastructure.
Karpenter manages compute.

---

## Architecture (simplified)

```
EKS Control Plane
        |
Baseline Node Group (On‑Demand, fixed)
        |
     Karpenter
        |
  Spot NodePools
  - ARM64 (preferred)
  - AMD64 (fallback)
```

---

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured
- kubectl
- Permissions for EKS, IAM, EC2, VPC, SQS

---

## Quick start

Note: set 
``` bash 
enable_karpenter_manifests=false // at first run in dev.tfvars
```
```bash
terraform init
terraform apply -var-file=dev.tfvars
```

Configure kubectl:

```bash
aws eks update-kubeconfig   --region $(terraform output -raw region)   --name   $(terraform output -raw cluster_name)
```

Verify:

```bash
kubectl get nodes
kubectl get nodepools
kubectl get ec2nodeclass
```

Run with nodepool manifests after intitial run:
set 

```bash
enable_karpenter_manifests=true
terraform apply -var-file=dev.tfvars
```


---

## Baseline vs Karpenter

### Baseline managed node group
- **On‑Demand by default**
- Fixed size (`min = max = desired`)
- Runs system workloads and Karpenter controller
- Not modified by Karpenter

### Karpenter
- Creates additional EC2 instances
- Uses Spot capacity
- Scales independently
- Terminates nodes when empty

Changing baseline size **does not affect** Karpenter.

---

## Graviton (ARM64)

- AWS Graviton = **ARM64**
- NodePools are architecture-specific
- Multi‑arch container images are required (most official images already are)

ARM64 is preferred for cost efficiency, AMD64 is used when required.

---

## Safe destroy order (important)

Karpenter creates EC2 instances outside Terraform.
Destroy in the correct order.

### Recommended (Terraform-only)

```bash
terraform destroy   -target=helm_release.karpenter   -target=helm_release.karpenter_crds

terraform destroy -var-file=dev.tfvars
```

### Alternative (manual)

```bash
kubectl delete nodepool --all
kubectl delete ec2nodeclass --all

terraform destroy -var-file=dev.tfvars
```

Do **not** run a full destroy while NodePools still exist.

---

## Karpenter PodDisruptionBudget (PDB)

- Ensures at least **one Karpenter controller** stays available during voluntary disruptions (e.g. node drains, upgrades).
- Reduces the risk of **scheduling stalls** caused by all Karpenter pods being evicted at once.
- Added as a **small safety net** for cluster stability; no changes are required in normal day‑to‑day use.

---

## Project structure

```
.
├── main.tf
├── versions.tf
├── variables.tf
├── outputs.tf
├── dev.tfvars
├── templates/
    ├── ec2nodeclass.yaml.tftpl
    ├── nodepool-spot-arm64.yaml
    └── nodepool-spot-amd64.yaml

```
