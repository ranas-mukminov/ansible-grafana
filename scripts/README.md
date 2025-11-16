# Grafana Utility Scripts

This directory contains utility scripts for managing and maintaining Grafana installations.

## Available Scripts

### 1. grafana-backup.sh

Comprehensive backup script for Grafana installations.

**Features:**
- Backs up Grafana database (SQLite, PostgreSQL, MySQL)
- Backs up configuration files
- Backs up data directory (plugins, dashboards, etc.)
- Creates timestamped archives
- Automatic cleanup of old backups
- Supports all database types

**Usage:**

```bash
# Basic usage (backs up to /backup/grafana)
sudo ./grafana-backup.sh

# Custom backup directory
sudo ./grafana-backup.sh /path/to/backup

# Automated with cron (daily at 2 AM)
0 2 * * * /usr/local/bin/grafana-backup.sh /backup/grafana >> /var/log/grafana-backup.log 2>&1
```

**Example Output:**

```
[INFO] Starting Grafana backup...
[INFO] Creating backup directory: /backup/grafana/grafana-backup-20231116_140532
[INFO] Backing up Grafana database...
[INFO] Detected SQLite database
[INFO] SQLite database backed up successfully
[INFO] Backing up Grafana configuration...
[INFO] Configuration backed up successfully
[INFO] Backing up Grafana data directory...
[INFO] Data directory backed up successfully
[INFO] Saving backup metadata...
[INFO] Creating final backup archive...
[INFO] Backup archive created: grafana-backup-20231116_140532.tar.gz (45M)
[INFO] Cleaning up old backups (keeping last 7 days)...
[INFO] Backup completed successfully!
[INFO] Backup location: /backup/grafana/grafana-backup-20231116_140532.tar.gz
```

**Restoration:**

```bash
# Extract backup
tar -xzf grafana-backup-20231116_140532.tar.gz
cd grafana-backup-20231116_140532

# Stop Grafana
sudo systemctl stop grafana-server

# Restore SQLite database
sudo cp grafana.db /var/lib/grafana/

# Restore configuration
sudo tar -xzf grafana-config.tar.gz -C /etc/

# Restore data
sudo tar -xzf grafana-data.tar.gz -C /var/lib/

# Fix permissions
sudo chown -R grafana:grafana /var/lib/grafana
sudo chown -R grafana:grafana /etc/grafana

# Start Grafana
sudo systemctl start grafana-server
```

### 2. grafana-healthcheck.sh

Advanced health check script with automatic recovery capabilities.

**Features:**
- HTTP/HTTPS health endpoint monitoring
- API health status checking
- Process and systemd service monitoring
- Database connection verification
- Automatic service restart on failure
- Configurable retry logic
- Alert notifications
- Detailed logging

**Usage:**

```bash
# Basic health check
./grafana-healthcheck.sh

# Custom URL and timeout
./grafana-healthcheck.sh -u http://grafana.example.com:3000 -t 5

# Disable auto-restart
./grafana-healthcheck.sh --no-restart

# Check with custom retry settings
./grafana-healthcheck.sh -r 5 -d 10

# Check with custom log file
./grafana-healthcheck.sh -l /var/log/my-grafana-check.log
```

**Options:**

```
-u, --url URL           Grafana URL (default: http://localhost:3000)
-t, --timeout SECONDS   Request timeout (default: 10)
-r, --retries NUMBER    Max retry attempts (default: 3)
-d, --delay SECONDS     Delay between retries (default: 5)
-l, --log FILE         Log file location (default: /var/log/grafana-healthcheck.log)
--no-restart           Disable automatic restart
-h, --help             Show help message
```

**Environment Variables:**

```bash
GRAFANA_URL=http://localhost:3000
GRAFANA_TIMEOUT=10
MAX_RETRIES=3
RETRY_DELAY=5
LOG_FILE=/var/log/grafana-healthcheck.log
AUTO_RESTART=true
ALERT_EMAIL=admin@example.com
```

**Automated Monitoring with Cron:**

```bash
# Check every 5 minutes
*/5 * * * * /usr/local/bin/grafana-healthcheck.sh >> /var/log/grafana-healthcheck.log 2>&1

# Check every minute with custom settings
* * * * * GRAFANA_URL=http://grafana.prod.example.com:3000 /usr/local/bin/grafana-healthcheck.sh
```

**Systemd Timer (Alternative to Cron):**

Create `/etc/systemd/system/grafana-healthcheck.service`:

```ini
[Unit]
Description=Grafana Health Check
After=grafana-server.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/grafana-healthcheck.sh
User=grafana
StandardOutput=journal
StandardError=journal
```

Create `/etc/systemd/system/grafana-healthcheck.timer`:

```ini
[Unit]
Description=Run Grafana Health Check every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

Enable the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now grafana-healthcheck.timer
```

## Installation

### Quick Install

```bash
# Download scripts
git clone https://github.com/ranas-mukminov/ansible-grafana.git
cd ansible-grafana/scripts

# Make executable
chmod +x grafana-backup.sh grafana-healthcheck.sh

# Copy to system path
sudo cp grafana-backup.sh /usr/local/bin/
sudo cp grafana-healthcheck.sh /usr/local/bin/
```

### Ansible Deployment

Create a playbook `deploy-scripts.yml`:

```yaml
---
- name: Deploy Grafana utility scripts
  hosts: grafana_servers
  become: true
  
  tasks:
    - name: Copy backup script
      copy:
        src: scripts/grafana-backup.sh
        dest: /usr/local/bin/grafana-backup.sh
        mode: '0755'
        owner: root
        group: root
    
    - name: Copy healthcheck script
      copy:
        src: scripts/grafana-healthcheck.sh
        dest: /usr/local/bin/grafana-healthcheck.sh
        mode: '0755'
        owner: root
        group: root
    
    - name: Create backup directory
      file:
        path: /backup/grafana
        state: directory
        mode: '0755'
    
    - name: Setup backup cron job
      cron:
        name: "Daily Grafana backup"
        hour: "2"
        minute: "0"
        job: "/usr/local/bin/grafana-backup.sh /backup/grafana >> /var/log/grafana-backup.log 2>&1"
    
    - name: Setup healthcheck cron job
      cron:
        name: "Grafana health check"
        minute: "*/5"
        job: "/usr/local/bin/grafana-healthcheck.sh >> /var/log/grafana-healthcheck.log 2>&1"
```

Deploy:

```bash
ansible-playbook -i inventory deploy-scripts.yml
```

## Advanced Configurations

### Remote Backup to S3

Extend the backup script to upload to S3:

```bash
#!/bin/bash
# Add to grafana-backup.sh after create_archive()

upload_to_s3() {
    if command -v aws &> /dev/null; then
        log_info "Uploading backup to S3..."
        aws s3 cp "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
            "s3://my-backups/grafana/" \
            --storage-class STANDARD_IA
        log_info "Backup uploaded to S3 successfully"
    fi
}
```

### Slack Notifications

Add Slack webhook to healthcheck script:

```bash
send_slack_alert() {
    local message="$1"
    local webhook_url="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"🚨 Grafana Alert: ${message}\"}" \
        "${webhook_url}"
}
```

### Email Alerts

Configure email alerts in healthcheck:

```bash
send_email_alert() {
    local message="$1"
    local email="${ALERT_EMAIL:-admin@example.com}"
    
    echo "${message}" | mail -s "[ALERT] Grafana Health Check" "${email}"
}
```

Install mail utilities:

```bash
# Debian/Ubuntu
sudo apt-get install mailutils

# RHEL/CentOS
sudo yum install mailx

# Configure with your SMTP settings
sudo dpkg-reconfigure postfix  # or configure /etc/postfix/main.cf
```

### Backup to Multiple Locations

```bash
# /etc/grafana-backup.conf
BACKUP_LOCATIONS=(
    "/backup/grafana"
    "/mnt/nfs-backup/grafana"
    "s3://my-backups/grafana"
)

for location in "${BACKUP_LOCATIONS[@]}"; do
    if [[ $location == s3://* ]]; then
        aws s3 cp backup.tar.gz "$location"
    else
        cp backup.tar.gz "$location"
    fi
done
```

## Monitoring with Prometheus

Export health check metrics for Prometheus:

Create `/usr/local/bin/grafana-healthcheck-exporter.sh`:

```bash
#!/bin/bash
# Exports Grafana health status for Prometheus node_exporter

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
mkdir -p "${TEXTFILE_DIR}"

if /usr/local/bin/grafana-healthcheck.sh --no-restart; then
    echo "grafana_health_status 1" > "${TEXTFILE_DIR}/grafana_health.prom"
else
    echo "grafana_health_status 0" > "${TEXTFILE_DIR}/grafana_health.prom"
fi

echo "grafana_health_check_timestamp $(date +%s)" >> "${TEXTFILE_DIR}/grafana_health.prom"
```

## Troubleshooting

### Backup fails with permission errors

```bash
# Fix permissions
sudo chown -R grafana:grafana /var/lib/grafana
sudo chmod -R 755 /var/lib/grafana

# Run backup as root
sudo ./grafana-backup.sh
```

### Healthcheck can't connect

```bash
# Check if Grafana is running
systemctl status grafana-server

# Check if port is listening
ss -tlnp | grep 3000

# Check firewall
sudo ufw status
sudo firewall-cmd --list-all

# Test manually
curl -v http://localhost:3000/api/health
```

### Logs not being written

```bash
# Check log file permissions
ls -la /var/log/grafana-*.log

# Create log file
sudo touch /var/log/grafana-backup.log
sudo touch /var/log/grafana-healthcheck.log
sudo chown grafana:grafana /var/log/grafana-*.log
```

## Best Practices

1. **Test backups regularly**
   ```bash
   # Monthly restore test
   ./grafana-backup.sh /tmp/test-backup
   # Restore to test instance and verify
   ```

2. **Monitor script execution**
   - Use systemd timers instead of cron for better logging
   - Set up alerting for script failures
   - Review logs regularly

3. **Keep multiple backup copies**
   - Local backups (fast recovery)
   - Remote backups (disaster recovery)
   - Offsite backups (geographic redundancy)

4. **Secure sensitive data**
   ```bash
   # Encrypt backups
   gpg --encrypt grafana-backup.tar.gz
   
   # Store credentials securely
   chmod 600 /etc/grafana-backup.conf
   ```

5. **Document recovery procedures**
   - Test restore process
   - Document RTO/RPO requirements
   - Train team members

## Contributing

Found a bug or have a feature request? Please open an issue or submit a pull request!

## License

These scripts are provided under the same MIT License as the main repository.
