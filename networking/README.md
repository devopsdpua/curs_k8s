# Gateway API (Envoy Gateway)

Манифесты применяются **после** `terraform apply`. Key Vault создаётся Terraform’ом (отдельная RG + KV); wildcard-сертификат загружаете в него вручную. В tfvars задайте при необходимости `key_vault_name`, `tls_cert_name` (имя серта в KV).

## Порядок применения

```bash
# 1. GatewayClass и Gateway
kubectl apply -f gateway-class.yaml
kubectl apply -f gateway.yaml

# 2. Wildcard TLS из Key Vault
# В secret-provider-class.yaml подставить: <KEYVAULT_NAME>, <CERT_NAME>, <TENANT_ID>, <KV_CSI_CLIENT_ID> (terraform output kv_csi_client_id)
kubectl apply -f secret-provider-class.yaml
kubectl apply -f cert-sync.yaml
kubectl get secret wildcard-tls -n default   # дождаться появления Secret

# 3. Маршруты (демо-бэкенд — Grafana, ставится Terraform’ом)
kubectl apply -f grafana-httproute.yaml      # path / → Grafana:3000
kubectl apply -f http-to-https-redirect.yaml # редирект HTTP → HTTPS
```

В `gateway.yaml` замените `*.example.com` на свой wildcard-домен. Для статического IP после `terraform apply` подставьте в `spec.addresses[0].value` вывод `terraform output -raw gateway_public_ip` (вместо `СТАТИЧЕСКИЙ_IP`), затем снова `kubectl apply -f gateway.yaml`.

Внешний IP: `kubectl get gateway default-gateway -n default`.
