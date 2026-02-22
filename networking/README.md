# Gateway API

После `terraform apply` загрузите wildcard-сертификат в Key Vault. В `secret-provider-class.yaml` и `cert-sync.yaml` подставьте: keyvaultName, tenantID (az account show --query tenantId -o tsv), clientID (terraform output -raw kv_csi_client_id).

```bash
kubectl apply -f gateway-class.yaml
kubectl apply -f gateway.yaml
kubectl apply -f secret-provider-class.yaml
kubectl apply -f cert-sync.yaml
kubectl get secret wildcard-tls -n default
kubectl apply -f grafana-httproute.yaml
kubectl apply -f http-to-https-redirect.yaml
```

IP Gateway: `terraform output -raw gateway_public_ip`. В gateway.yaml hostname и value подставляются Terraform при manage_gateway_api.
