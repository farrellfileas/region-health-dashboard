# OCI Region Health Dashboard

A production-grade SRE platform running on Oracle Kubernetes Engine (OKE), built to demonstrate end-to-end infrastructure ownership: Terraform provisioning, Kubernetes operations, GitOps deployment, and full-stack observability.

## Architecture

```
Internet
   │
   ▼
Load Balancer (10.0.2.0/24)
   │
   ▼
OKE Worker Nodes (10.0.1.0/24)      OKE Endpoint (10.0.0.0/24)
   ├── FastAPI (2 replicas)
   ├── Frontend (1–2 replicas)
   ├── Postgres (StatefulSet + PVC)
   ├── Prometheus
   ├── Grafana
   └── Loki
```

**Cloud:** OCI Free Tier (Always Free)
**Cluster:** OKE Basic Cluster — 2x `VM.Standard.E5.Flex` (2 OCPU / 16 GB RAM each)
**Total capacity:** 4 OCPU, 32 GB RAM, ~106 GB usable block volume

## Stack

| Layer | Technology |
|---|---|
| Infrastructure | Terraform + OCI |
| Orchestration | OKE (Kubernetes) |
| API | FastAPI (Python 3.11) |
| Database | Postgres 15 (StatefulSet) |
| Frontend | Static HTML |
| Metrics | Prometheus + `prometheus-fastapi-instrumentator` |
| Dashboards | Grafana (SLO burn rates, incident MTTR) |
| Logging | structlog → Loki → Grafana |
| CI | GitHub Actions (build / test / scan / push to OCIR) |
| CD | ArgoCD (GitOps, watches `k8s/overlays/`) |

## Repo Structure

```
.
├── terraform/infra/        # OCI infrastructure — apply manually from WSL2
├── app/
│   ├── api/                # FastAPI service
│   ├── frontend/           # HTML status page
│   └── postgres/           # K8s manifests + SQL schema
├── k8s/
│   ├── base/               # Raw Kubernetes manifests
│   └── overlays/
│       ├── dev/            # Kustomize overlay — dev
│       └── prod/           # Kustomize overlay — prod
├── observability/
│   ├── prometheus/
│   ├── grafana/
│   └── loki/
├── .github/workflows/
│   ├── ci-api.yml          # API build, test, scan, push
│   ├── ci-frontend.yml     # Frontend build, scan, push
│   └── cd.yml              # Placeholder — ArgoCD owns CD
└── runbooks/
```

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Liveness + Postgres connectivity check |
| `GET` | `/metrics` | Prometheus metrics scrape endpoint |
| `GET` | `/incidents` | Last 50 incidents ordered by `started_at` |

### `/health` response

```json
{ "status": "ok", "database": "connected" }
```

Returns `503` with `"status": "degraded"` if Postgres is unreachable.

### `/incidents` response

```json
{
  "incidents": [
    {
      "id": 1,
      "region": "us-phoenix-1",
      "severity": "P2",
      "title": "Elevated error rate on compute API",
      "started_at": "2026-04-18T14:00:00Z",
      "resolved_at": "2026-04-18T15:30:00Z"
    }
  ]
}
```

## Database Schema

```sql
CREATE TABLE incidents (
    id          SERIAL PRIMARY KEY,
    region      VARCHAR(64)  NOT NULL,
    severity    VARCHAR(4)   NOT NULL CHECK (severity IN ('P1','P2','P3','P4')),
    title       TEXT         NOT NULL,
    started_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);
```

## Infrastructure

Terraform is applied manually from WSL2 — never via CI.

```bash
cd terraform/infra
terraform init
terraform plan
terraform apply
```

**Required `terraform.tfvars` (gitignored):**

```hcl
tenancy_ocid     = "ocid1.tenancy.oc1..."
user_ocid        = "ocid1.user.oc1..."
compartment_id   = "ocid1.compartment.oc1..."
fingerprint      = "xx:xx:xx:..."
private_key_path = "~/.oci/oci_api_key.pem"
region           = "us-phoenix-1"
```

Remote state is stored in OCI Object Storage via the S3-compatible backend configured in `backend.tf`.

## Kubernetes

Manifests live in `k8s/base/`. Kustomize overlays in `k8s/overlays/dev` and `k8s/overlays/prod` patch environment-specific values.

ArgoCD syncs automatically on merge to `main`.

**Manual apply (dev only):**

```bash
kubectl apply -k k8s/overlays/dev
```

**Namespace:** `oci-health`

All workloads use `app.kubernetes.io/` labels and explicit resource requests/limits.

## CI Pipeline

GitHub Actions runs independent workflows triggered by changes to specific app components.

### `ci-api.yml`
Triggers on changes to `app/api/**`:

1. Test FastAPI with Postgres (pytest)
2. Build API Docker image and push to OCIR
3. Scan image for critical vulnerabilities (Trivy)
4. Tag as `:latest`
5. Update `k8s/base/api/deployment.yaml` with new image SHA

### `ci-frontend.yml`
Triggers on changes to `app/frontend/**`:

1. Build frontend Docker image and push to OCIR
2. Scan image for critical vulnerabilities (Trivy)
3. Tag as `:latest`
4. Update `k8s/base/frontend/deployment.yaml` with new image SHA

**Note:** Changes to `app/postgres/**` do not trigger either workflow. Database schema is applied during deployment.

All secrets (`OCIR_TOKEN`, `OCIR_USERNAME`, `OCIR_REGISTRY`, `OCIR_NAMESPACE`) are stored in GitHub Actions secrets — never in code.

## Observability

- **Prometheus** scrapes `/metrics` from the FastAPI pods
- **Grafana** displays SLO dashboards including error-budget burn rates and incident MTTR
- **Loki** ingests structured JSON logs emitted by `structlog`

Log format (stdout):

```json
{"event": "health_check", "status": "ok", "level": "info", "timestamp": "2026-04-20T10:00:00Z"}
```

## Local Development

```bash
# API
cd app/api
pip install -r requirements.txt
DATABASE_URL=postgresql://health:health@localhost:5432/health uvicorn main:app --reload

# Frontend
open app/frontend/index.html
```

## Prerequisites

| Tool | Version |
|---|---|
| kubectl | 1.35+ |
| Terraform | 1.14+ |
| Helm | 3.20+ |
| OCI CLI | 3.78+ |
| Docker | 29+ |
