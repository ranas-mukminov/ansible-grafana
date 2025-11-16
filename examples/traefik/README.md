# Traefik Reverse Proxy Configuration for Grafana

This directory contains Traefik configuration files for using Traefik as a reverse proxy for Grafana.

## Overview

Traefik is a modern HTTP reverse proxy and load balancer that makes deploying microservices easy. It supports automatic HTTPS with Let's Encrypt, dynamic configuration, and many other features.

## Files

- `traefik.yml` - Main static configuration for Traefik
- `grafana-dynamic.yml` - Dynamic configuration for Grafana routing

## Prerequisites

- Traefik v2.x or v3.x installed
- Grafana running on localhost:3000
- Domain name pointing to your server

## Installation

### Option 1: Install Traefik with Docker

```bash
# Create directories
mkdir -p /etc/traefik/dynamic
mkdir -p /var/log/traefik

# Create acme.json for Let's Encrypt
touch /etc/traefik/acme.json
chmod 600 /etc/traefik/acme.json

# Copy configuration files
cp traefik.yml /etc/traefik/
cp grafana-dynamic.yml /etc/traefik/dynamic/

# Update domain in configuration
sed -i 's/grafana.example.com/your-domain.com/g' /etc/traefik/dynamic/grafana-dynamic.yml

# Run Traefik with Docker
docker run -d \
  --name traefik \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/traefik:/etc/traefik \
  -v /var/log/traefik:/var/log/traefik \
  traefik:latest
```

### Option 2: Install Traefik as System Service

```bash
# Download Traefik binary
wget https://github.com/traefik/traefik/releases/download/v2.10.0/traefik_v2.10.0_linux_amd64.tar.gz
tar -xzf traefik_v2.10.0_linux_amd64.tar.gz
sudo mv traefik /usr/local/bin/
sudo chmod +x /usr/local/bin/traefik

# Create user and directories
sudo useradd -r -s /bin/false traefik
sudo mkdir -p /etc/traefik/dynamic
sudo mkdir -p /var/log/traefik

# Copy configuration
sudo cp traefik.yml /etc/traefik/
sudo cp grafana-dynamic.yml /etc/traefik/dynamic/

# Set permissions
sudo touch /etc/traefik/acme.json
sudo chmod 600 /etc/traefik/acme.json
sudo chown -R traefik:traefik /etc/traefik /var/log/traefik

# Create systemd service
sudo tee /etc/systemd/system/traefik.service << EOF
[Unit]
Description=Traefik
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=traefik
Group=traefik
ExecStart=/usr/local/bin/traefik --configFile=/etc/traefik/traefik.yml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=traefik

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Traefik
sudo systemctl daemon-reload
sudo systemctl enable traefik
sudo systemctl start traefik
```

### Option 3: Deploy with Ansible

Create `setup-traefik.yml`:

```yaml
---
- name: Install and configure Traefik for Grafana
  hosts: grafana_servers
  become: true

  vars:
    traefik_version: "2.10.0"
    grafana_domain: grafana.example.com
    letsencrypt_email: admin@example.com

  tasks:
    - name: Download Traefik binary
      get_url:
        url: "https://github.com/traefik/traefik/releases/download/v{{ traefik_version }}/traefik_v{{ traefik_version }}_linux_amd64.tar.gz"
        dest: /tmp/traefik.tar.gz

    - name: Extract Traefik
      unarchive:
        src: /tmp/traefik.tar.gz
        dest: /tmp/
        remote_src: true

    - name: Install Traefik binary
      copy:
        src: /tmp/traefik
        dest: /usr/local/bin/traefik
        mode: '0755'
        remote_src: true

    - name: Create Traefik user
      user:
        name: traefik
        system: true
        shell: /bin/false

    - name: Create Traefik directories
      file:
        path: "{{ item }}"
        state: directory
        owner: traefik
        group: traefik
        mode: '0755'
      loop:
        - /etc/traefik
        - /etc/traefik/dynamic
        - /var/log/traefik

    - name: Copy Traefik configuration
      template:
        src: traefik.yml.j2
        dest: /etc/traefik/traefik.yml
        owner: traefik
        group: traefik
        mode: '0644'

    - name: Copy dynamic configuration
      template:
        src: grafana-dynamic.yml.j2
        dest: /etc/traefik/dynamic/grafana.yml
        owner: traefik
        group: traefik
        mode: '0644'

    - name: Create acme.json
      file:
        path: /etc/traefik/acme.json
        state: touch
        owner: traefik
        group: traefik
        mode: '0600'

    - name: Install systemd service
      copy:
        dest: /etc/systemd/system/traefik.service
        content: |
          [Unit]
          Description=Traefik
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=simple
          User=traefik
          Group=traefik
          ExecStart=/usr/local/bin/traefik --configFile=/etc/traefik/traefik.yml
          Restart=always
          RestartSec=5

          [Install]
          WantedBy=multi-user.target

    - name: Enable and start Traefik
      systemd:
        name: traefik
        enabled: true
        state: started
        daemon_reload: true

    - name: Configure firewall
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: tcp
      loop:
        - "80"
        - "443"
      when: ansible_os_family == "Debian"
```

Deploy:

```bash
ansible-playbook setup-traefik.yml
```

## Configuration

### Static Configuration (traefik.yml)

The static configuration defines:
- Entry points (HTTP/HTTPS)
- Certificate resolvers (Let's Encrypt)
- Providers (file-based dynamic config)
- Logging

### Dynamic Configuration (grafana-dynamic.yml)

The dynamic configuration defines:
- Routers (URL routing rules)
- Services (backend servers)
- Middlewares (headers, rate limiting, etc.)

### Customization

Edit `grafana-dynamic.yml` to customize:

1. **Change domain:**
   ```yaml
   rule: "Host(`your-domain.com`)"
   ```

2. **Add authentication:**
   ```yaml
   middlewares:
     grafana-auth:
       basicAuth:
         users:
           - "admin:$apr1$H6uskkkW$IgXLP6ewTrSuBkTrqE8wj/"
   ```

3. **Configure load balancing:**
   ```yaml
   services:
     grafana-service:
       loadBalancer:
         servers:
           - url: "http://grafana1:3000"
           - url: "http://grafana2:3000"
           - url: "http://grafana3:3000"
         sticky:
           cookie:
             name: grafana_session
   ```

4. **Add IP whitelist:**
   ```yaml
   middlewares:
     grafana-ipwhitelist:
       ipWhiteList:
         sourceRange:
           - "192.168.1.0/24"
           - "10.0.0.0/8"
   ```

## Docker Compose Integration

If you're running Grafana with Docker, you can use labels instead of file-based configuration:

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:latest
    command:
      - --providers.docker=true
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.letsencrypt.acme.httpchallenge=true
      - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.letsencrypt.acme.email=admin@example.com
      - --certificatesresolvers.letsencrypt.acme.storage=/acme.json
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/acme.json

  grafana:
    image: grafana/grafana:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.example.com`)"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"
```

## Monitoring Traefik

### Access Logs

```bash
# View access logs
tail -f /var/log/traefik/access.log

# View Traefik logs
tail -f /var/log/traefik/traefik.log

# With journalctl (systemd)
journalctl -u traefik -f
```

### Traefik Dashboard

Enable the dashboard in `traefik.yml`:

```yaml
api:
  dashboard: true
  insecure: false  # Set to true for development only
```

Access at: `http://localhost:8080` (if insecure is true)

For production, secure the dashboard:

```yaml
# In grafana-dynamic.yml
http:
  routers:
    traefik-dashboard:
      rule: "Host(`traefik.example.com`)"
      service: api@internal
      middlewares:
        - traefik-auth

  middlewares:
    traefik-auth:
      basicAuth:
        users:
          - "admin:$apr1$H6uskkkW$IgXLP6ewTrSuBkTrqE8wj/"
```

### Prometheus Metrics

Enable metrics in `traefik.yml`:

```yaml
metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
    buckets:
      - 0.1
      - 0.3
      - 1.0
      - 3.0
      - 10.0
```

Metrics available at: `http://localhost:8080/metrics`

## Troubleshooting

### Certificate issues

```bash
# Check ACME logs
grep -i acme /var/log/traefik/traefik.log

# Remove and regenerate certificates
rm /etc/traefik/acme.json
touch /etc/traefik/acme.json
chmod 600 /etc/traefik/acme.json
systemctl restart traefik
```

### Routing issues

```bash
# Check configuration syntax
traefik --configFile=/etc/traefik/traefik.yml --dry-run

# Verify dynamic configuration is loaded
curl http://localhost:8080/api/http/routers

# Test backend connectivity
curl http://localhost:3000/api/health
```

### Permission errors

```bash
# Fix ownership
chown -R traefik:traefik /etc/traefik /var/log/traefik

# Fix acme.json permissions
chmod 600 /etc/traefik/acme.json
```

## Advanced Features

### Automatic certificate renewal

Traefik handles Let's Encrypt certificate renewal automatically. No cron jobs needed!

### Middleware chaining

Combine multiple middlewares:

```yaml
routers:
  grafana:
    middlewares:
      - grafana-headers
      - grafana-ratelimit
      - grafana-ipwhitelist
      - grafana-auth
```

### Circuit breaker

Add resilience:

```yaml
middlewares:
  grafana-circuit-breaker:
    circuitBreaker:
      expression: NetworkErrorRatio() > 0.30
```

### Retry middleware

```yaml
middlewares:
  grafana-retry:
    retry:
      attempts: 3
      initialInterval: 100ms
```

## Security Best Practices

1. **Always use HTTPS in production**
2. **Enable HTTP to HTTPS redirect**
3. **Use strong TLS ciphers**
4. **Enable security headers**
5. **Implement rate limiting**
6. **Use authentication where appropriate**
7. **Keep Traefik updated**
8. **Monitor access logs**

## Additional Resources

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Traefik Community Forum](https://community.traefik.io/)
