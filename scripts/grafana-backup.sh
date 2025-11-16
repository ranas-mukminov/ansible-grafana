#!/bin/bash
#
# Grafana Backup Script
# This script backs up Grafana database, configuration, and dashboards
#
# Usage: sudo ./grafana-backup.sh [backup_dir]
#

set -euo pipefail

# Configuration
BACKUP_DIR="${1:-/backup/grafana}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
GRAFANA_DATA_DIR="/var/lib/grafana"
GRAFANA_CONFIG_DIR="/etc/grafana"
BACKUP_NAME="grafana-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_grafana_installed() {
    if ! command -v grafana-server &> /dev/null; then
        log_error "Grafana is not installed"
        exit 1
    fi
}

create_backup_dir() {
    log_info "Creating backup directory: ${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}"
}

backup_database() {
    log_info "Backing up Grafana database..."
    
    # Detect database type from grafana.ini
    DB_TYPE=$(grep -E "^type\s*=" "${GRAFANA_CONFIG_DIR}/grafana.ini" | awk '{print $3}' || echo "sqlite3")
    
    case "${DB_TYPE}" in
        sqlite3)
            log_info "Detected SQLite database"
            if [[ -f "${GRAFANA_DATA_DIR}/grafana.db" ]]; then
                cp "${GRAFANA_DATA_DIR}/grafana.db" "${BACKUP_PATH}/grafana.db"
                log_info "SQLite database backed up successfully"
            else
                log_warn "SQLite database not found at ${GRAFANA_DATA_DIR}/grafana.db"
            fi
            ;;
        
        postgres|postgresql)
            log_info "Detected PostgreSQL database"
            DB_HOST=$(grep -E "^host\s*=" "${GRAFANA_CONFIG_DIR}/grafana.ini" | awk '{print $3}' || echo "127.0.0.1:5432")
            DB_NAME=$(grep -E "^name\s*=" "${GRAFANA_CONFIG_DIR}/grafana.ini" | awk '{print $3}' || echo "grafana")
            DB_USER=$(grep -E "^user\s*=" "${GRAFANA_CONFIG_DIR}/grafana.ini" | awk '{print $3}' || echo "grafana")
            
            if command -v pg_dump &> /dev/null; then
                pg_dump -h "${DB_HOST%%:*}" -U "${DB_USER}" "${DB_NAME}" > "${BACKUP_PATH}/grafana-db.sql"
                log_info "PostgreSQL database backed up successfully"
            else
                log_error "pg_dump not found. Install postgresql-client to backup PostgreSQL database"
            fi
            ;;
        
        mysql)
            log_info "Detected MySQL database"
            DB_HOST=$(grep -E "^host\s*=" "${GRAFANA_CONFIG_DIR}/grafana.ini" | awk '{print $3}' || echo "127.0.0.1:3306")
            DB_NAME=$(grep -E "^name\s*=" "${GRAFANA_CONFIG_DIR}/grafana.ini" | awk '{print $3}' || echo "grafana")
            DB_USER=$(grep -E "^user\s*=" "${GRAFANA_CONFIG_DIR}/grafana.ini" | awk '{print $3}' || echo "grafana")
            
            if command -v mysqldump &> /dev/null; then
                mysqldump -h "${DB_HOST%%:*}" -u "${DB_USER}" -p "${DB_NAME}" > "${BACKUP_PATH}/grafana-db.sql"
                log_info "MySQL database backed up successfully"
            else
                log_error "mysqldump not found. Install mysql-client to backup MySQL database"
            fi
            ;;
        
        *)
            log_warn "Unknown database type: ${DB_TYPE}"
            ;;
    esac
}

backup_config() {
    log_info "Backing up Grafana configuration..."
    
    if [[ -d "${GRAFANA_CONFIG_DIR}" ]]; then
        tar -czf "${BACKUP_PATH}/grafana-config.tar.gz" -C "$(dirname ${GRAFANA_CONFIG_DIR})" "$(basename ${GRAFANA_CONFIG_DIR})"
        log_info "Configuration backed up successfully"
    else
        log_warn "Configuration directory not found: ${GRAFANA_CONFIG_DIR}"
    fi
}

backup_data() {
    log_info "Backing up Grafana data directory..."
    
    if [[ -d "${GRAFANA_DATA_DIR}" ]]; then
        # Exclude database file to avoid duplication
        tar -czf "${BACKUP_PATH}/grafana-data.tar.gz" \
            --exclude="grafana.db" \
            -C "$(dirname ${GRAFANA_DATA_DIR})" "$(basename ${GRAFANA_DATA_DIR})"
        log_info "Data directory backed up successfully"
    else
        log_warn "Data directory not found: ${GRAFANA_DATA_DIR}"
    fi
}

save_metadata() {
    log_info "Saving backup metadata..."
    
    cat > "${BACKUP_PATH}/backup-info.txt" << EOF
Grafana Backup Information
==========================
Backup Date: $(date)
Hostname: $(hostname)
Grafana Version: $(grafana-server -v 2>/dev/null || echo "Unknown")
Database Type: ${DB_TYPE:-Unknown}
Backup Directory: ${BACKUP_PATH}

Files Included:
EOF
    
    ls -lh "${BACKUP_PATH}" >> "${BACKUP_PATH}/backup-info.txt"
}

create_archive() {
    log_info "Creating final backup archive..."
    
    cd "${BACKUP_DIR}"
    tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"
    
    # Calculate size
    SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
    log_info "Backup archive created: ${BACKUP_NAME}.tar.gz (${SIZE})"
    
    # Remove temporary directory
    rm -rf "${BACKUP_NAME}"
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (keeping last 7 days)..."
    
    # Remove backups older than 7 days
    find "${BACKUP_DIR}" -name "grafana-backup-*.tar.gz" -mtime +7 -delete
    
    log_info "Old backups cleaned up"
}

main() {
    log_info "Starting Grafana backup..."
    
    check_root
    check_grafana_installed
    create_backup_dir
    backup_database
    backup_config
    backup_data
    save_metadata
    create_archive
    cleanup_old_backups
    
    log_info "Backup completed successfully!"
    log_info "Backup location: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    
    # Print restore instructions
    cat << EOF

${GREEN}Backup completed!${NC}

To restore from this backup:
1. Extract: tar -xzf ${BACKUP_NAME}.tar.gz
2. Stop Grafana: sudo systemctl stop grafana-server
3. Restore database (SQLite): sudo cp grafana.db ${GRAFANA_DATA_DIR}/
4. Restore config: sudo tar -xzf grafana-config.tar.gz -C /etc/
5. Restore data: sudo tar -xzf grafana-data.tar.gz -C /var/lib/
6. Start Grafana: sudo systemctl start grafana-server

For PostgreSQL/MySQL databases, restore using pg_restore or mysql commands.
EOF
}

# Run main function
main "$@"
