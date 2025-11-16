# Grafana Deployment Examples

This directory contains alternative deployment methods and configurations for Grafana. These examples are particularly useful if you're migrating away from this deprecated role or want to use container-based deployments.

## Directory Structure

```
examples/
├── docker/          # Docker and Docker Compose deployments
├── podman/          # Podman deployments (RHEL, Fedora, Arch Linux)
├── nginx/           # Nginx reverse proxy configurations
├── traefik/         # Traefik reverse proxy configurations
└── kubernetes/      # Kubernetes manifests
```

## Quick Links

- **[Docker Deployment](docker/)** - Deploy Grafana using Docker Compose
- **[Podman Deployment](podman/)** - Deploy Grafana using Podman (ideal for Arch Linux)
- **[Nginx Reverse Proxy](nginx/)** - Configure Nginx as reverse proxy
- **[Traefik Configuration](traefik/)** - Configure Traefik for Grafana
- **[Kubernetes Deployment](kubernetes/)** - Deploy Grafana on Kubernetes

## When to Use These Examples

### Use Docker/Podman if:
- ✅ You want container-based deployments
- ✅ You need easy rollbacks and upgrades
- ✅ You're on Arch Linux or other systems with Podman
- ✅ You want to avoid package management complexities
- ✅ You need to run multiple Grafana instances

### Use Nginx/Traefik if:
- ✅ You need SSL/TLS termination
- ✅ You want to use a custom domain
- ✅ You need load balancing across multiple Grafana instances
- ✅ You want advanced routing and middleware

### Use Kubernetes if:
- ✅ You're already running Kubernetes
- ✅ You need high availability
- ✅ You want automated scaling
- ✅ You need to integrate with other K8s services

## Docker Deployment

### Prerequisites
- Docker 20.10+
- Docker Compose 2.0+

### Quick Start

```bash
cd examples/docker
cp docker-compose.yml /opt/grafana/
cd /opt/grafana

# Create .env file
cat > .env << EOF
GRAFANA_ADMIN_PASSWORD=your-secure-password
POSTGRES_PASSWORD=your-postgres-password
GRAFANA_SECRET_KEY=$(openssl rand -base64 32)
EOF

# Start Grafana
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs -f grafana
```

### Using Ansible

```bash
ansible-playbook -i inventory examples/docker/deploy-docker.yml --ask-vault-pass
```

## Podman Deployment

### Prerequisites
- Podman 4.0+
- podman-compose (optional)

### Quick Start

```bash
# Install Podman
# Arch Linux
sudo pacman -S podman

# Fedora/RHEL
sudo dnf install podman

# Deploy with Ansible
ansible-playbook -i inventory examples/podman/deploy-podman.yml --ask-vault-pass
```

### Manual Podman Deployment

```bash
# Create pod
podman pod create --name grafana-pod -p 3000:3000

# Run Grafana
podman run -d \
  --name grafana \
  --pod grafana-pod \
  -v grafana-data:/var/lib/grafana:Z \
  -e GF_SECURITY_ADMIN_PASSWORD=changeme \
  docker.io/grafana/grafana:latest

# Generate systemd service
podman generate systemd --new --name grafana-pod > /etc/systemd/system/grafana-pod.service

# Enable and start
systemctl enable --now grafana-pod
```

## Nginx Reverse Proxy

### Prerequisites
- Nginx 1.18+
- Certbot (for Let's Encrypt SSL)

### Quick Setup

```bash
# Deploy with Ansible
ansible-playbook -i inventory examples/nginx/setup-nginx.yml \
  -e "grafana_domain=grafana.example.com" \
  -e "nginx_ssl_cert_email=admin@example.com"
```

### Manual Setup

```bash
# Copy configuration
sudo cp examples/nginx/grafana.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/grafana.conf /etc/nginx/sites-enabled/

# Update domain name
sudo sed -i 's/grafana.example.com/your-domain.com/g' /etc/nginx/sites-available/grafana.conf

# Obtain SSL certificate
sudo certbot --nginx -d your-domain.com

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

## High Availability Setup

For production deployments, consider using:

### PostgreSQL Backend

```yaml
# docker-compose.yml
services:
  grafana:
    environment:
      - GF_DATABASE_TYPE=postgres
      - GF_DATABASE_HOST=postgres:5432
      - GF_DATABASE_NAME=grafana
      - GF_DATABASE_USER=grafana
      - GF_DATABASE_PASSWORD=${POSTGRES_PASSWORD}
```

### Redis for Sessions

```yaml
services:
  grafana:
    environment:
      - GF_REMOTE_CACHE_TYPE=redis
      - GF_REMOTE_CACHE_CONNSTR=addr=redis:6379,pool_size=100
```

### Multiple Grafana Instances with Load Balancer

```nginx
# /etc/nginx/conf.d/grafana-upstream.conf
upstream grafana_backend {
    least_conn;
    server grafana1:3000 max_fails=3 fail_timeout=30s;
    server grafana2:3000 max_fails=3 fail_timeout=30s;
    server grafana3:3000 max_fails=3 fail_timeout=30s;
}

server {
    location / {
        proxy_pass http://grafana_backend;
        ...
    }
}
```

## Monitoring and Maintenance

### Health Checks

```bash
# Check Grafana health
curl http://localhost:3000/api/health

# Docker health
docker-compose ps

# Podman health
podman healthcheck run grafana
```

### Logs

```bash
# Docker logs
docker-compose logs -f grafana

# Podman logs
podman logs -f grafana

# Systemd logs (Podman)
journalctl -u pod-grafana-pod -f
```

### Backups

```bash
# Backup Grafana data
docker-compose exec grafana /bin/sh -c 'tar czf - /var/lib/grafana' > grafana-backup.tar.gz

# Podman backup
podman exec grafana tar czf - /var/lib/grafana > grafana-backup.tar.gz
```

### Updates

```bash
# Docker update
cd /opt/grafana
docker-compose pull
docker-compose up -d

# Podman update
podman pull docker.io/grafana/grafana:latest
systemctl restart pod-grafana-pod
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker-compose logs grafana
# or
podman logs grafana

# Check permissions
ls -la /var/lib/grafana-data
chown -R 472:472 /var/lib/grafana-data
```

### Can't access Grafana

```bash
# Check if container is running
docker-compose ps
# or
podman ps

# Check port binding
ss -tlnp | grep 3000

# Check firewall
sudo ufw status
sudo firewall-cmd --list-all
```

### SSL certificate issues

```bash
# Renew certificate
sudo certbot renew

# Check certificate expiry
sudo certbot certificates

# Test Nginx config
sudo nginx -t
```

## Security Best Practices

1. **Use Ansible Vault for secrets**
   ```bash
   ansible-vault create secrets.yml
   ```

2. **Set strong admin password**
   ```bash
   GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
   ```

3. **Enable HTTPS**
   - Use Let's Encrypt with certbot
   - Or provide your own certificates

4. **Restrict network access**
   ```yaml
   # docker-compose.yml
   services:
     grafana:
       networks:
         - internal
   ```

5. **Regular backups**
   - Automate backups with cron
   - Test restore procedures

6. **Keep containers updated**
   ```bash
   # Weekly update cron
   0 3 * * 0 cd /opt/grafana && docker-compose pull && docker-compose up -d
   ```

## Additional Resources

- [Grafana Docker Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/)
- [Grafana Configuration Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)
- [Grafana High Availability](https://grafana.com/docs/grafana/latest/setup-grafana/set-up-for-high-availability/)

## Getting Help

If you encounter issues:

1. Check the [Grafana Community Forums](https://community.grafana.com/)
2. Review [Grafana Documentation](https://grafana.com/docs/)
3. Open an issue on the [official Grafana repository](https://github.com/grafana/grafana/issues)
