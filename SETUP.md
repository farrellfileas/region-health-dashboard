# Setup Guide — Replicating the Deployment

This guide walks through deploying the Region Health Dashboard in your own OCI tenancy.

## Prerequisites

| Tool | Version | Used For |
|---|---|---|
| kubectl | 1.35+ | Deploy and manage Kubernetes resources |
| Terraform | 1.14+ | Provision OCI infrastructure (VCN, OKE cluster, nodes) |
| OCI CLI | 3.78+ | Retrieve kubeconfig and manage OCI resources |
| Helm | 3.20+ | Deploy observability stack (Prometheus, Grafana, Loki) |

**Note:** Docker is not required locally if using GitHub Actions for CI/CD. The CI workflows handle image building and pushing to the registry.

## Deployment Steps Provision Infrastructure with Terraform

```bash
cd terraform/infra
terraform init
terraform plan
terraform apply
```

This creates: VCN with 3 subnets, ENHANCED_CLUSTER, 2-node pool, security rules.

**Required:** Create `terraform.tfvars` with your OCI credentials (gitignored):

```hcl
tenancy_ocid     = "ocid1.tenancy.oc1.oc1..."
user_ocid        = "ocid1.user.oc1.oc1..."
compartment_id   = "ocid1.compartment.oc1..."
fingerprint      = "xx:xx:xx:..."
private_key_path = "~/.oci/oci_api_key.pem"
region           = "us-phoenix-1"
```

Terraform will output the cluster ID and endpoint — save these for the next step.

## Step 2: Get Kubeconfig

```bash
oci ce cluster create-kubeconfig --region us-phoenix-1 --cluster-id <cluster-id>
kubectl cluster-info
```

This configures `kubectl` to connect to your OKE cluster.

## Step 3: Create Namespace and Image Pull Secret

```bash
kubectl create namespace region-health

kubectl create secret docker-registry ocir-secret \
  --docker-server=phx.ocir.io \
  --docker-username='<namespace>/<username>' \
  --docker-password='<auth-token>' \
  --docker-email='<email>' \
  -n region-health
```

Replace with your OCIR credentials. The `<auth-token>` is an OCI auth token (not your password).

## Step 4: Install ingress-nginx Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f helm/ingress-nginx/values.yaml
```

**Note on `helm/ingress-nginx/values.yaml`:** The file contains a hardcoded subnet OCID that points to your load balancer subnet. This is environment-specific and safe to keep in version control — OCIDs are not secrets, they are resource identifiers. If replicating in a different OCI environment, update the subnet annotation to match your LB subnet OCID.

This installs an ingress controller and exposes the cluster via an OCI Load Balancer.

## Step 5: Install ArgoCD

ArgoCD is not installed via Helm in this setup — only the Application custom resource is applied:

```bash
kubectl create namespace argocd

# Install ArgoCD manually or via your preferred method, then:
kubectl apply -f argocd/app.yaml
```

ArgoCD will now watch `k8s/base` and automatically sync all resources into the `region-health` namespace.

## Step 6: Install Observability Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Prometheus (standalone, not kube-prometheus-stack)
helm install prometheus prometheus-community/prometheus \
  --namespace region-health \
  -f helm/prometheus/values.yaml

# Grafana
helm install grafana grafana/grafana \
  --namespace region-health \
  -f helm/grafana/values.yaml

# Loki
helm install loki grafana/loki \
  --namespace region-health \
  -f helm/loki/values.yaml

# Promtail (log forwarder)
helm install promtail grafana/promtail \
  --namespace region-health \
  -f helm/promtail/values.yaml
```

## Step 7: Verify All Pods Are Running

```bash
kubectl get pods -n region-health
```

Expected pods:
- `api-*` (2 replicas)
- `frontend-*` (1-2 replicas)
- `postgres-0` (StatefulSet)
- `prometheus-*` (1 replica)
- `grafana-*` (1 replica)
- `loki-*` (1 replica)

All should show `STATUS: Running`.

## Step 8: Seed Demo Data (Optional)

Once Postgres is running, seed the incidents table:

```bash
kubectl exec -it postgres-0 -n region-health -- psql -U postgres-user -d health -c "
INSERT INTO incidents (region, severity, title, started_at, resolved_at)
VALUES
    ('us-phoenix-1', 'P1', 'Elevated error rate on compute API', now() - interval '2 hours', now() - interval '1 hour 30 minutes'),
    ('us-phoenix-1', 'P2', 'Database connection pool exhaustion', now() - interval '4 hours', now() - interval '3 hours 45 minutes'),
    ('eu-amsterdam-1', 'P2', 'High latency on object storage', now() - interval '6 hours', now() - interval '5 hours 20 minutes'),
    ('us-ashburn-1', 'P3', 'Prometheus scrape interval increased', now() - interval '12 hours', now() - interval '11 hours 50 minutes')
ON CONFLICT DO NOTHING;
"
```

## Step 9: Access the System

Get the load balancer IP:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

The `EXTERNAL-IP` is your entry point. Visit `http://<external-ip>` in your browser to see the frontend dashboard.

## Troubleshooting

**Postgres pod stuck in `Init:0/1` or CrashLoopBackOff`:**
Check if the schema ConfigMap was created:
```bash
kubectl get configmap postgres-schema -n region-health
```

If missing, ArgoCD may not have synced yet. Force a sync or check ArgoCD logs.

**Pods pending due to resource constraints:**
With 2 nodes at 2 OCPU / 16GB each, total capacity is 4 OCPU / 32GB. Some workloads may not fit if resource requests are too high. Reduce replica counts or resource requests in the manifests.

**API can't connect to Postgres:**
Verify the secret was created with correct credentials:
```bash
kubectl get secret postgres-secret -n region-health -o yaml
```

## Next Steps

- Fork this repository and update CI secrets (OCIR_TOKEN, OCIR_USERNAME, etc.) in GitHub Actions
- Push code changes to trigger the CI pipeline and watch ArgoCD auto-sync
- Explore the Grafana dashboards and Prometheus queries
