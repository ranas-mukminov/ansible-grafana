# Migration Guide: cloudalchemy.grafana → grafana.grafana

This guide helps you migrate from the deprecated `cloudalchemy.grafana` role to the official `grafana.grafana` collection.

## Table of Contents

- [Why Migrate?](#why-migrate)
- [Prerequisites](#prerequisites)
- [Backup Before Migration](#backup-before-migration)
- [Step-by-Step Migration](#step-by-step-migration)
- [Variable Mapping](#variable-mapping)
- [Common Migration Scenarios](#common-migration-scenarios)
- [Alternative: Container-Based Deployment](#alternative-container-based-deployment)
- [Troubleshooting](#troubleshooting)

## Why Migrate?

The official `grafana.grafana` collection provides:

| Feature | cloudalchemy.grafana | grafana.grafana |
|---------|---------------------|-----------------|
| Active Maintenance | ❌ Deprecated | ✅ Yes |
| Grafana v11+ Support | ❌ No | ✅ Yes |
| Grafana Cloud API | ❌ No | ✅ Yes |
| Alloy/Loki/Mimir/Tempo | ❌ No | ✅ Yes |
| OpenTelemetry | ❌ No | ✅ Yes |
| Security Updates | ❌ No | ✅ Regular |

## Prerequisites

1. **Ansible Version**: 2.9 or higher
2. **Python**: 3.6 or higher
3. **Access**: SSH access to your Grafana servers
4. **Permissions**: Sudo/root access for package management

## Backup Before Migration

**CRITICAL**: Always backup before migrating!

### 1. Backup Grafana Database

```bash
# For SQLite (default)
sudo cp /var/lib/grafana/grafana.db /backup/grafana.db.$(date +%Y%m%d)

# For PostgreSQL
pg_dump -h localhost -U grafana grafana > /backup/grafana-db-$(date +%Y%m%d).sql

# For MySQL
mysqldump -u grafana -p grafana > /backup/grafana-db-$(date +%Y%m%d).sql
```

### 2. Backup Configuration

```bash
sudo tar -czf /backup/grafana-config-$(date +%Y%m%d).tar.gz \
    /etc/grafana/ \
    /var/lib/grafana/
```

### 3. Backup Dashboards (if not provisioned)

```bash
# Using the backup script provided in this repo
sudo bash scripts/grafana-backup.sh
```

### 4. Document Current Configuration

```bash
# Save current installed version
grafana-server -v > /backup/grafana-version.txt

# Save installed plugins
grafana-cli plugins ls > /backup/grafana-plugins.txt

# Save configuration
sudo cat /etc/grafana/grafana.ini > /backup/grafana.ini.backup
```

## Step-by-Step Migration

### Step 1: Install Official Collection

```bash
ansible-galaxy collection install grafana.grafana
```

Verify installation:

```bash
ansible-galaxy collection list | grep grafana
```

### Step 2: Update Your Inventory

Your inventory structure remains the same:

```ini
[grafana]
grafana01.example.com
grafana02.example.com
```

### Step 3: Update Playbook Structure

**Before (cloudalchemy.grafana):**

```yaml
---
- hosts: grafana
  roles:
    - cloudalchemy.grafana
  vars:
    grafana_security:
      admin_password: "secret"
    grafana_datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus:9090
```

**After (grafana.grafana):**

```yaml
---
- hosts: grafana
  collections:
    - grafana.grafana
  roles:
    - grafana.grafana.grafana
  vars:
    grafana_security:
      admin_user: admin
      admin_password: "{{ vault_grafana_password }}"
```

### Step 4: Migrate Variables

See [Variable Mapping](#variable-mapping) section below.

### Step 5: Test in Staging

**IMPORTANT**: Test on a non-production environment first!

```bash
# Dry run
ansible-playbook -i staging grafana.yml --check --diff

# Apply to staging
ansible-playbook -i staging grafana.yml

# Verify
curl -u admin:password http://staging-grafana:3000/api/health
```

### Step 6: Migrate Production

```bash
# Final backup
ansible-playbook -i production backup-grafana.yml

# Apply migration
ansible-playbook -i production grafana.yml

# Verify health
ansible-playbook -i production verify-grafana.yml
```

## Variable Mapping

Most variables remain the same, but here are the key differences:

### Security Variables

```yaml
# Old (cloudalchemy)
grafana_security:
  admin_password: "secret"

# New (grafana.grafana) - Use Ansible Vault!
grafana_security:
  admin_user: admin
  admin_password: "{{ vault_grafana_password }}"
```

### Datasource Configuration

The datasource configuration is now handled via API modules:

**Before:**

```yaml
grafana_datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    basicAuth: false
```

**After (using modules):**

```yaml
- name: Configure Prometheus datasource
  grafana.grafana.datasource:
    name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    grafana_url: "{{ grafana_url }}"
    grafana_user: "{{ grafana_security.admin_user }}"
    grafana_password: "{{ grafana_security.admin_password }}"
```

### Dashboard Import

**Before:**

```yaml
grafana_dashboards:
  - dashboard_id: '1860'
    revision_id: '4'
    datasource: 'Prometheus'
```

**After:**

```yaml
- name: Import Node Exporter Dashboard
  grafana.grafana.dashboard:
    dashboard_id: 1860
    dashboard_revision: 4
    folder: Kubernetes
    grafana_url: "{{ grafana_url }}"
    grafana_user: "{{ grafana_security.admin_user }}"
    grafana_password: "{{ grafana_security.admin_password }}"
```

### Plugin Installation

**Before:**

```yaml
grafana_plugins:
  - grafana-piechart-panel
  - grafana-clock-panel
```

**After (remains similar but better managed):**

```yaml
grafana_plugins:
  - name: grafana-piechart-panel
    version: latest
  - name: grafana-clock-panel
    version: 1.3.0
```

## Common Migration Scenarios

### Scenario 1: Basic Grafana with Prometheus

**Complete Before Example:**

```yaml
---
- hosts: monitoring
  roles:
    - cloudalchemy.grafana
  vars:
    grafana_security:
      admin_password: "MySecretPassword"
    grafana_datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: 'http://localhost:9090'
    grafana_plugins:
      - grafana-piechart-panel
```

**Complete After Example:**

```yaml
---
- hosts: monitoring
  collections:
    - grafana.grafana
  
  tasks:
    - name: Install and configure Grafana
      include_role:
        name: grafana.grafana.grafana
      vars:
        grafana_security:
          admin_user: admin
          admin_password: "{{ vault_grafana_password }}"
        grafana_plugins:
          - name: grafana-piechart-panel
            version: latest
    
    - name: Configure Prometheus datasource
      grafana.grafana.datasource:
        name: Prometheus
        type: prometheus
        url: http://localhost:9090
        access: proxy
        grafana_url: "http://localhost:3000"
        grafana_user: admin
        grafana_password: "{{ vault_grafana_password }}"
```

### Scenario 2: Multiple Datasources and Dashboards

```yaml
---
- hosts: grafana_servers
  collections:
    - grafana.grafana
  
  vars_files:
    - vault.yml  # Contains encrypted passwords
  
  roles:
    - grafana.grafana.grafana
  
  post_tasks:
    - name: Configure datasources
      grafana.grafana.datasource:
        name: "{{ item.name }}"
        type: "{{ item.type }}"
        url: "{{ item.url }}"
        access: proxy
        grafana_url: "{{ grafana_url }}"
        grafana_user: admin
        grafana_password: "{{ vault_grafana_password }}"
      loop:
        - { name: 'Prometheus', type: 'prometheus', url: 'http://prometheus:9090' }
        - { name: 'Loki', type: 'loki', url: 'http://loki:3100' }
        - { name: 'Tempo', type: 'tempo', url: 'http://tempo:3200' }
    
    - name: Import dashboards
      grafana.grafana.dashboard:
        dashboard_id: "{{ item.id }}"
        dashboard_revision: "{{ item.revision }}"
        folder: "{{ item.folder }}"
        grafana_url: "{{ grafana_url }}"
        grafana_user: admin
        grafana_password: "{{ vault_grafana_password }}"
      loop:
        - { id: 1860, revision: 27, folder: 'Node Exporter' }
        - { id: 7362, revision: 5, folder: 'Kubernetes' }
```

### Scenario 3: High Availability Setup

```yaml
---
- hosts: grafana_cluster
  collections:
    - grafana.grafana
  
  vars:
    grafana_database:
      type: postgres
      host: postgres-ha.example.com:5432
      name: grafana
      user: grafana
      password: "{{ vault_postgres_password }}"
    
    grafana_remote_cache:
      type: redis
      connstr: "addr=redis.example.com:6379,pool_size=100,db=0"
    
    grafana_server:
      protocol: http
      http_port: 3000
      domain: grafana.example.com
      root_url: "https://grafana.example.com/"
  
  roles:
    - grafana.grafana.grafana
```

## Alternative: Container-Based Deployment

If you prefer containers, consider these alternatives instead of the Ansible role:

### Option 1: Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-piechart-panel,grafana-clock-panel
    volumes:
      - grafana-storage:/var/lib/grafana
      - ./provisioning:/etc/grafana/provisioning
    networks:
      - monitoring

volumes:
  grafana-storage:

networks:
  monitoring:
    driver: bridge
```

Deploy with Ansible:

```yaml
---
- hosts: grafana
  tasks:
    - name: Install Docker
      apt:
        name:
          - docker.io
          - docker-compose
        state: present
    
    - name: Copy docker-compose file
      copy:
        src: docker-compose.yml
        dest: /opt/grafana/docker-compose.yml
    
    - name: Start Grafana container
      docker_compose:
        project_src: /opt/grafana
        state: present
```

### Option 2: Podman with Systemd

For systems using Podman (like Arch Linux):

```yaml
---
- hosts: grafana
  tasks:
    - name: Install Podman
      package:
        name: podman
        state: present
    
    - name: Create Grafana pod
      containers.podman.podman_pod:
        name: grafana-pod
        state: started
        ports:
          - "3000:3000"
    
    - name: Run Grafana container
      containers.podman.podman_container:
        name: grafana
        image: grafana/grafana:latest
        state: started
        pod: grafana-pod
        env:
          GF_SECURITY_ADMIN_PASSWORD: "{{ vault_grafana_password }}"
          GF_INSTALL_PLUGINS: "grafana-piechart-panel"
        volume:
          - grafana-storage:/var/lib/grafana
    
    - name: Generate systemd unit for Grafana pod
      containers.podman.podman_generate_systemd:
        name: grafana-pod
        dest: /etc/systemd/system/
        restart_policy: always
    
    - name: Enable Grafana service
      systemd:
        name: pod-grafana-pod
        enabled: yes
        state: started
```

### Option 3: Kubernetes/OpenShift

For Kubernetes deployments, use the Grafana Helm chart:

```bash
# Add Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --create-namespace \
  --set adminPassword='SecurePassword' \
  --set persistence.enabled=true \
  --set persistence.size=10Gi
```

Or deploy with Ansible using the kubernetes.core collection:

```yaml
---
- hosts: localhost
  collections:
    - kubernetes.core
  
  tasks:
    - name: Create Grafana namespace
      k8s:
        name: monitoring
        api_version: v1
        kind: Namespace
        state: present
    
    - name: Deploy Grafana
      k8s:
        state: present
        definition:
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: grafana
            namespace: monitoring
          spec:
            replicas: 1
            selector:
              matchLabels:
                app: grafana
            template:
              metadata:
                labels:
                  app: grafana
              spec:
                containers:
                  - name: grafana
                    image: grafana/grafana:latest
                    ports:
                      - containerPort: 3000
                    env:
                      - name: GF_SECURITY_ADMIN_PASSWORD
                        valueFrom:
                          secretKeyRef:
                            name: grafana-secrets
                            key: admin-password
```

## Troubleshooting

### Issue: "Collection not found"

**Solution:**

```bash
# Install collection globally
ansible-galaxy collection install grafana.grafana

# Or specify collection path
ansible-galaxy collection install grafana.grafana -p ./collections
```

Then update ansible.cfg:

```ini
[defaults]
collections_paths = ./collections
```

### Issue: "Module not found"

**Solution:**

Ensure you're using the collection namespace:

```yaml
# Wrong
- name: Add datasource
  datasource:
    ...

# Correct
- name: Add datasource
  grafana.grafana.datasource:
    ...
```

### Issue: Authentication failures

**Solution:**

1. Verify credentials:

```bash
curl -u admin:password http://localhost:3000/api/health
```

2. Check Grafana logs:

```bash
sudo journalctl -u grafana-server -f
```

3. Use Ansible Vault for passwords:

```bash
ansible-vault create vault.yml
```

Add:

```yaml
vault_grafana_password: YourSecurePassword
```

Use in playbook:

```bash
ansible-playbook -i inventory grafana.yml --ask-vault-pass
```

### Issue: Dashboards not importing

**Solution:**

1. Check dashboard ID is valid on grafana.com
2. Verify datasource name matches exactly
3. Use debug mode:

```yaml
- name: Import dashboard
  grafana.grafana.dashboard:
    dashboard_id: 1860
    ...
  register: result
  
- debug:
    var: result
```

### Issue: Plugins not installing

**Solution:**

```bash
# Manual plugin installation
grafana-cli plugins install <plugin-name>

# Restart Grafana
sudo systemctl restart grafana-server
```

## Additional Resources

- [Official Grafana Ansible Collection Documentation](https://github.com/grafana/grafana-ansible-collection)
- [Grafana Documentation](https://grafana.com/docs/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Ansible Vault Guide](https://docs.ansible.com/ansible/latest/user_guide/vault.html)

## Getting Help

If you encounter issues during migration:

1. Check the [official collection issues](https://github.com/grafana/grafana-ansible-collection/issues)
2. Review [Grafana Community Forums](https://community.grafana.com/)
3. Consult [Ansible Galaxy](https://galaxy.ansible.com/grafana/grafana)

## Contributing

Found an issue with this migration guide? Please open an issue or submit a pull request!
