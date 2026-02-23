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
   This creates: Envoy Gateway Helm release, Argo CD (in namespace `argocd`), GatewayClass, Gateway, HTTPRoute for Argo CD. Terraform may also update AKS/jumpbox state — that is normal.

5. Argo CD is installed in namespace `argocd`. To get the initial admin password:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   ```
   Log in at `https://argocd.bkgdsvc.com` (after DNS and TLS are set up; see sections 5–6). Username is `admin`.

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
| Jumpbox | Argo CD: get admin password from secret `argocd-initial-admin-secret` in namespace `argocd` |
| Jumpbox | Add git repo to ArgoCD, set `manage_monitoring`, `mimir_storage_account_name`, `git_repo_url` in tfvars → `terraform apply` |
| Jumpbox | Verify: `kubectl -n argocd get applications` — mimir, alloy, grafana should be Synced/Healthy |
| Optional | HTTP→HTTPS redirect, DNS to gateway_public_ip (e.g. `argocd.bkgdsvc.com`, `grafana.bkgdsvc.com`) |

After that the cluster is ready: Envoy Gateway serves HTTPS for `*.bkgdsvc.com` with TLS from Key Vault. Argo CD is installed by Terraform in namespace `argocd`.

---

## 7. Monitoring stack (Alloy → Mimir → Grafana)

The monitoring stack is deployed via ArgoCD Applications. Terraform creates the Azure infrastructure (Storage Account, Workload Identity) and the ArgoCD Application CRDs; ArgoCD syncs the Helm charts from this repo.

### Prerequisites

- `manage_monitoring = true` in `terraform.tfvars`
- `mimir_storage_account_name` set to a globally unique name (e.g. `stmimirstudy42`)
- `git_repo_url` set to the HTTPS or SSH URL of this repository (ArgoCD must have access)

### What Terraform creates

| Resource | Purpose |
|----------|---------|
| Storage Account + Blob container `mimir-data` | Long-term metrics storage for Mimir |
| Managed Identity `id-aks-mimir` | Workload Identity for Mimir → Blob access |
| Federated Identity Credential | Links K8s SA `mimir` in ns `mimir` to the Azure identity |
| Role Assignment `Storage Blob Data Contributor` | Grants Mimir write/read access to the storage account |
| ArgoCD Applications (mimir, alloy, grafana) | ArgoCD syncs Helm charts from `apps/monitoring/` |

### What ArgoCD deploys

| Application | Namespace | Chart |
|-------------|-----------|-------|
| mimir | `mimir` | `grafana/mimir-distributed` — microservices mode, Azure Blob backend |
| alloy | `alloy` | `grafana/alloy` — DaemonSet, scrapes kubelet/cAdvisor/pods, remote_write to Mimir |
| grafana | `monitoring` | `grafana/grafana` — standalone, Mimir as Prometheus datasource |

### Steps (on jumpbox, after section 3)

1. Ensure `terraform.tfvars` includes:
   ```hcl
   manage_monitoring          = true
   mimir_storage_account_name = "stmimirstudy42"   # must be globally unique
   git_repo_url               = "https://github.com/<you>/curs-k8s.git"
   ```

2. Add the git repo to ArgoCD (if not already added):
   ```bash
   kubectl -n argocd exec -it deploy/argocd-server -- argocd repo add https://github.com/<you>/curs-k8s.git --username <user> --password <token>
   ```
   Or via the ArgoCD UI: Settings → Repositories → Connect Repo.

3. Run Terraform:
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```
   This creates the Storage Account, Workload Identity, and ArgoCD Applications.

4. ArgoCD will automatically sync the three applications. Monitor progress:
   ```bash
   kubectl -n argocd get applications
   ```

5. Verify the stack:
   ```bash
   kubectl get pods -n mimir          # Mimir components
   kubectl get pods -n alloy          # Alloy DaemonSet
   kubectl get pods -n monitoring     # Grafana
   ```

6. Grafana is accessible at `https://grafana.bkgdsvc.com` (after DNS is set up).
   Default admin password: check `kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d`.

### Architecture

```
Alloy (DaemonSet, ns: alloy)
  │  scrapes kubelet, cAdvisor, annotated pods
  │  remote_write
  ▼
Mimir Gateway (ns: mimir)  ──►  Distributor → Ingester → Azure Blob Storage
  ▲                                                        ▲
  │  PromQL queries                                        │
Grafana (ns: monitoring)            Compactor, Store-Gateway ─┘
```

---

## If http://argocd.bkgdsvc.com does not open

1. **DNS** — `argocd.bkgdsvc.com` must resolve to the gateway public IP:
   ```bash
   terraform output -raw gateway_public_ip   # e.g. 20.224.253.127
   ```
   Create an **A record** for `argocd.bkgdsvc.com` (or `*.bkgdsvc.com`) pointing to that IP. Check: `nslookup argocd.bkgdsvc.com` or `dig argocd.bkgdsvc.com`.

2. **Gateway API CRDs** — Without them, Gateway and HTTPRoute have no effect. On the jumpbox:
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
   ```

3. **Check gateway and route** (on jumpbox):
   ```bash
   kubectl get gateway -A
   kubectl get httproute -A
   kubectl get svc -n envoy-gateway-system   # Envoy LB should get the gateway public IP
   kubectl get svc -n argocd                 # argocd-server should exist
   ```

4. **Test without DNS** — From the jumpbox, if DNS is not set yet:
   ```bash
   curl -v -H "Host: argocd.bkgdsvc.com" http://$(terraform output -raw gateway_public_ip)/
   ```
   If this works but the browser does not, the issue is DNS on your machine.

5. **If curl returns 500 Internal Server Error** — Traffic reaches Envoy but the gateway cannot use the backend (`response_code_details: direct_response`, `upstream_cluster: null` in Envoy logs). Ensure a **ReferenceGrant** exists and the controller has re-processed the route:
   - Apply the grant if needed: `kubectl apply -f networking/routes/argocd-reference-grant.yaml`
   - Verify: `kubectl get referencegrant -n argocd`
   - Restart the Envoy Gateway controller so it re-resolves the HTTPRoute backend:  
     `kubectl rollout restart deployment envoy-gateway -n envoy-gateway-system`
   - Wait ~30s, then retry: `curl -v -H "Host: argocd.bkgdsvc.com" http://<gateway-ip>/`  
   If it still returns 500, check Envoy logs:  
   `kubectl logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=default-gateway -c envoy --tail=50`.

6. **If curl hangs (e.g. "Trying 20.x.x.x:80..." with no response)** — TCP never reaches the gateway. Check:
   - **Try the other EXTERNAL-IP** from `kubectl get svc -n envoy-gateway-system` (e.g. `52.149.x.x`):
     ```bash
     curl -v -H "Host: argocd.bkgdsvc.com" http://52.149.111.244/
     ```
     If this works, the static IP may not be bound correctly to the Load Balancer.
   - **Azure Load Balancer health** — In Azure Portal: go to the **node resource group** (e.g. `MC_rg-learning-aks_aks-study-cluster_westeurope`), open the **Load Balancer** (name often contains `kubernetes`). Check **Backend pools**: are backends **Healthy**? Check **Health probes**: if the probe fails, the LB will not forward traffic and `curl` will hang. Fix or align the probe with the Envoy listener.
   - **NSG** — The node subnet may have an NSG that blocks inbound from the internet. In the same node resource group, open the **Network security group** linked to the AKS subnet and add an **Inbound** rule: Allow TCP, source `0.0.0.0/0` or `Internet`, destination port range `30000-32767` (NodePort range), priority e.g. `4000`. Then retry `curl` to the gateway public IP.

7. **Static gateway IP (20.x) not accepting traffic** — If the other EXTERNAL-IP (e.g. `52.149.x.x`) works but `terraform output gateway_public_ip` (20.224.253.127) hangs or times out:
   - **Diagnosis (Azure Portal):** In the **node resource group** (e.g. `MC_rg-learning-aks_aks-study-cluster_westeurope`), open the **Load Balancer**. Under **Frontend IP configuration**: if **20.224.253.127 is not listed at all**, the static PIP was never attached as a frontend (PIP exists in the node RG but the Service did not use it). If both 52.x and 20.x are listed, check **Load balancing rules** — each frontend needs its own rules; if only 52.x is used, add rules for 20.x (Fix B).
   - **Fix A1 — Recreate the Service (preferred):** So the controller recreates the Service and Azure uses the static PIP. On the jumpbox:
     ```bash
     kubectl delete svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=default-gateway
     ```
     Wait 1–2 minutes for the controller to recreate the service. Then: `kubectl get svc -n envoy-gateway-system`. Ideally there is a single EXTERNAL-IP (20.224.253.127). Test: `curl -v -H "Host: argocd.bkgdsvc.com" http://20.224.253.127/`.
   - **Fix A2 — EnvoyProxy with Azure PIP annotations:** Terraform applies an EnvoyProxy (`envoy-proxy-azure-pip`) linked to the Gateway with annotations so the Envoy Service uses the existing PIP in the node resource group. After `terraform apply`, **recreate the Service (A1)** so the new Service is created with these annotations and the static IP is attached. If the static IP was not in Frontend IP configuration at all, apply Terraform (to create EnvoyProxy and link Gateway to it), then run the A1 delete command; after the controller recreates the Service, check Frontend IP configuration again for 20.224.253.127.
   - **Fix B — Add rules for the static frontend in Azure:** In the same Load Balancer, create **new** load balancing rules for TCP 80 and TCP 443 that use **Frontend IP** 20.224.253.127 (same backend pool and health probe as the existing rules). No Terraform/Kubernetes changes; repeat or automate if the LB is recreated.

8. **HTTPS** — For `https://argocd.bkgdsvc.com` you need the wildcard cert in Key Vault (`k8s-bkgdsvc-cert`) and the cert-sync pod (section 5). Until then, use **http://** (or the curl test above).
