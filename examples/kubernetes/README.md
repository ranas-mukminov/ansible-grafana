# Kubernetes Deployment Examples for Grafana

This directory contains Kubernetes manifests for deploying Grafana in a Kubernetes cluster.

## Prerequisites

- Kubernetes cluster (v1.19+)
- kubectl configured
- Ingress controller (nginx, traefik, etc.)
- cert-manager (optional, for automatic SSL certificates)
- Persistent storage provisioner

## Quick Deployment

### Option 1: Using kubectl

```bash
# Deploy all resources
kubectl apply -f grafana-deployment.yaml

# Check deployment status
kubectl -n monitoring get pods
kubectl -n monitoring get svc
kubectl -n monitoring get ingress

# Get admin credentials
kubectl -n monitoring get secret grafana-secrets -o jsonpath='{.data.admin-password}' | base64 -d
```

### Option 2: Using Ansible

Create `deploy-k8s.yml`:

```yaml
---
- name: Deploy Grafana on Kubernetes
  hosts: localhost
  connection: local
  collections:
    - kubernetes.core

  vars:
    grafana_namespace: monitoring
    grafana_domain: grafana.example.com
    grafana_admin_password: "{{ vault_grafana_password }}"

  tasks:
    - name: Create namespace
      k8s:
        state: present
        definition:
          apiVersion: v1
          kind: Namespace
          metadata:
            name: "{{ grafana_namespace }}"

    - name: Deploy Grafana resources
      k8s:
        state: present
        src: grafana-deployment.yaml
        namespace: "{{ grafana_namespace }}"

    - name: Wait for Grafana to be ready
      k8s_info:
        kind: Deployment
        namespace: "{{ grafana_namespace }}"
        name: grafana
      register: deployment
      until: deployment.resources[0].status.readyReplicas | default(0) >= 1
      retries: 30
      delay: 10
```

Deploy:

```bash
ansible-playbook deploy-k8s.yml --ask-vault-pass
```

### Option 3: Using Helm

```bash
# Add Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --create-namespace \
  --set adminPassword='changeme' \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set ingress.enabled=true \
  --set ingress.hosts[0]=grafana.example.com

# Get admin password
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

## Configuration

### Storage

The deployment uses a PersistentVolumeClaim (PVC) for data persistence:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

To use a specific storage class:

```yaml
spec:
  storageClassName: fast-ssd
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

### Secrets Management

**Important**: Never commit secrets to version control!

#### Using Sealed Secrets

```bash
# Install sealed-secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml

# Create sealed secret
echo -n 'your-password' | kubectl create secret generic grafana-secrets \
  --dry-run=client \
  --from-file=admin-password=/dev/stdin \
  -o yaml | \
  kubeseal -o yaml > grafana-sealed-secret.yaml

# Apply sealed secret
kubectl apply -f grafana-sealed-secret.yaml
```

#### Using External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-secrets
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: grafana-secrets
  data:
    - secretKey: admin-password
      remoteRef:
        key: secret/grafana
        property: admin-password
```

### High Availability Setup

For production HA deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
spec:
  replicas: 3  # Multiple replicas
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - grafana
              topologyKey: kubernetes.io/hostname
      containers:
        - name: grafana
          env:
            - name: GF_DATABASE_TYPE
              value: postgres
            - name: GF_DATABASE_HOST
              value: postgresql:5432
            - name: GF_DATABASE_NAME
              value: grafana
            - name: GF_DATABASE_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: username
            - name: GF_DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: password
```

### Datasource Provisioning

Add datasources via ConfigMaps:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus-service:9090
        isDefault: true

  loki.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki:3100

  tempo.yaml: |
    apiVersion: 1
    datasources:
      - name: Tempo
        type: tempo
        access: proxy
        url: http://tempo:3200
```

### Dashboard Provisioning

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards-config
data:
  dashboards.yaml: |
    apiVersion: 1
    providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        updateIntervalSeconds: 10
        allowUiUpdates: true
        options:
          path: /var/lib/grafana/dashboards

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
data:
  kubernetes.json: |
    {
      "dashboard": { ... }
    }
```

## Ingress Configuration

### Nginx Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - grafana.example.com
      secretName: grafana-tls
  rules:
    - host: grafana.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
```

### Traefik Ingress

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`grafana.example.com`)
      kind: Rule
      services:
        - name: grafana
          port: 3000
  tls:
    certResolver: letsencrypt
```

## Monitoring

### ServiceMonitor for Prometheus Operator

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: grafana
  endpoints:
    - port: http-grafana
      path: /metrics
```

## Backup and Restore

### Backup

```bash
# Backup using kubectl
kubectl -n monitoring exec deployment/grafana -- \
  tar czf - /var/lib/grafana > grafana-backup-$(date +%Y%m%d).tar.gz

# Backup using Velero
velero backup create grafana-backup \
  --include-namespaces monitoring \
  --include-resources persistentvolumeclaims,secrets,configmaps
```

### Restore

```bash
# Restore from tar backup
kubectl -n monitoring exec deployment/grafana -- \
  tar xzf - -C / < grafana-backup-20231116.tar.gz

# Restart pods
kubectl -n monitoring rollout restart deployment/grafana

# Restore using Velero
velero restore create --from-backup grafana-backup
```

## Troubleshooting

### Pod not starting

```bash
# Check pod status
kubectl -n monitoring get pods

# View pod logs
kubectl -n monitoring logs -f deployment/grafana

# Describe pod for events
kubectl -n monitoring describe pod <pod-name>

# Check persistent volume
kubectl -n monitoring get pvc
kubectl -n monitoring describe pvc grafana-pvc
```

### Permission issues

```bash
# Fix ownership (if using hostPath)
kubectl -n monitoring exec deployment/grafana -- chown -R 472:472 /var/lib/grafana

# Check security context
kubectl -n monitoring get pod <pod-name> -o yaml | grep -A 10 securityContext
```

### Ingress not working

```bash
# Check ingress
kubectl -n monitoring get ingress
kubectl -n monitoring describe ingress grafana

# Check ingress controller logs
kubectl -n ingress-nginx logs deployment/ingress-nginx-controller -f

# Test service directly
kubectl -n monitoring port-forward svc/grafana 3000:3000
```

## Scaling

### Horizontal Pod Autoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: grafana
  namespace: monitoring
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: grafana
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

## Security Best Practices

1. **Use secrets for sensitive data**
   ```bash
   kubectl create secret generic grafana-secrets \
     --from-literal=admin-password=$(openssl rand -base64 32)
   ```

2. **Enable RBAC**
   ```yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     name: grafana
   rules:
     - apiGroups: [""]
       resources: ["configmaps", "secrets"]
       verbs: ["get", "list", "watch"]
   ```

3. **Use network policies**
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: grafana
   spec:
     podSelector:
       matchLabels:
         app: grafana
     ingress:
       - from:
           - namespaceSelector:
               matchLabels:
                 name: ingress-nginx
   ```

4. **Enable Pod Security Standards**
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: monitoring
     labels:
       pod-security.kubernetes.io/enforce: restricted
   ```

## Additional Resources

- [Grafana on Kubernetes Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/installation/kubernetes/)
- [Grafana Helm Chart](https://github.com/grafana/helm-charts)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
