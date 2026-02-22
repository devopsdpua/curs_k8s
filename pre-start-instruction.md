# pre-start-instruction

Step-by-step setup: laptop → jumpbox → TLS and routes.

---

## 1. Local (laptop)

**Requirements:** Azure CLI, Terraform >=1.9, `az login`, subscription selected.

1. In the repo root create `terraform.tfvars` (not committed to git):
   ```hcl
   subscription_id         = "<your-subscription-id>"
   resource_group_name     = "rg-learning-aks"
   resource_group_location = "West Europe"
   key_vault_name          = "kv-curs-k8s"
   kube_config_path        = ""
   jumpbox_admin_password  = "<password>"
   ```
   Subscription ID: `az account show --query id -o tsv`.

2. Run:
   ```bash
   terraform init
   terraform apply -var-file=terraform.tfvars
   ```
   This creates: RGs, AKS (private), VNet, Key Vault, jumpbox, Envoy Gateway PIP, Workload Identity for KV. Helm and K8s manifests are not applied when `kube_config_path` is empty.

3. Save these outputs for later:
   ```bash
   terraform output -raw jumpbox_public_ip
   terraform output -raw gateway_public_ip
   terraform output -raw kv_csi_client_id
   ```

---

## 2. Move to jumpbox

**Option A — via git (recommended)**

- Commit and push your changes (excluding `terraform.tfvars`, `config/`, `*.tfstate` — they are in .gitignore).
- On jumpbox: `git clone <repo>` or `git pull` in an existing clone.

**Option B — copy state and code**

- Copy the project directory to the jumpbox (including `terraform.tfstate`, `terraform.tfstate.backup`, `.terraform.lock.hcl`). You can omit `.terraform` and run `terraform init` on the jumpbox.

On the jumpbox create `terraform.tfvars` (not in the repo):
- Same variables as locally, but set `kube_config_path` to the kubeconfig path **on the jumpbox**, e.g.:
  - if running Terraform as root: `kube_config_path = "/root/.kube/config"`
  - if as azureuser: `kube_config_path = "/home/azureuser/.kube/config"`

---

## 3. On jumpbox: cluster access and second apply

1. SSH in: `ssh azureuser@<jumpbox_public_ip>` (or root if configured that way).

2. Install Azure CLI if needed, log into the subscription:
   ```bash
   az login
   ```

3. Get kubeconfig:
   ```bash
   az aks get-credentials --resource-group rg-learning-aks --name aks-study-cluster
   ```
   Check: `kubectl get nodes`.

4. In the repo directory on the jumpbox run:
   ```bash
   terraform init
   terraform apply -var-file=terraform.tfvars
   ```
   This creates: Envoy Gateway Helm release, GatewayClass, Gateway, HTTPRoutes for ArgoCD and Grafana. Terraform may also update AKS/jumpbox state — that is normal.

---

## 4. Gateway API CRDs

On the jumpbox (with the same kubeconfig):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```

You can skip this if CRDs were already installed.

---

## 5. Wildcard TLS from Key Vault

1. Upload the wildcard certificate to Key Vault under the name `k8s-bkgdsvc-cert` (portal or `az keyvault secret set`). The name must match `objectName` in SecretProviderClass.

2. In `networking/tls/secret-provider-class.yaml` and `networking/tls/cert-sync.yaml` set:
   - `tenantID`: `az account show --query tenantId -o tsv`
   - `clientID`: `terraform output -raw kv_csi_client_id` (same in both files and in the cert-sync pod label).

3. Apply and restart the pod:
   ```bash
   kubectl apply -f networking/tls/secret-provider-class.yaml
   kubectl apply -f networking/tls/cert-sync.yaml
   kubectl delete pod -n default -l app=cert-sync
   ```

4. Wait for the Secret to appear:
   ```bash
   kubectl get secret wildcard-tls -n default
   ```

---

## 6. Optional

- HTTP to HTTPS redirect: `kubectl apply -f networking/routes/http-to-https-redirect.yaml`
- DNS: A record for `*.bkgdsvc.com` (or required hosts) pointing to `terraform output -raw gateway_public_ip`.

---

## Checklist

| Where | Action |
|-------|--------|
| Laptop | tfvars with `kube_config_path = ""` → `terraform init` + `apply` |
| Laptop → jumpbox | git push + on jumpbox git pull (or copy state and code) |
| Jumpbox | Create tfvars with kubeconfig path on jumpbox |
| Jumpbox | `az login`, `az aks get-credentials`, `terraform init` + `apply` |
| Jumpbox | `kubectl apply` Gateway API CRDs (standard-install.yaml) |
| Jumpbox | Secret in KV `k8s-bkgdsvc-cert`, set tenantID/clientID in SecretProviderClass and cert-sync → apply + delete cert-sync pod |
| Optional | HTTP→HTTPS redirect, DNS to gateway_public_ip |

After that the cluster is ready: Envoy Gateway serves HTTPS for `*.bkgdsvc.com` with TLS from Key Vault. ArgoCD and Grafana are not installed by this repo — routes for them exist; install the backends separately.
