#!/bin/bash
#
# Grafana Health Check Script
# Monitors Grafana instance health and automatically restarts if needed
#
# Usage: ./grafana-healthcheck.sh
#

set -euo pipefail

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_TIMEOUT="${GRAFANA_TIMEOUT:-10}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"
LOG_FILE="${LOG_FILE:-/var/log/grafana-healthcheck.log}"
AUTO_RESTART="${AUTO_RESTART:-true}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

check_http_health() {
    local url="${GRAFANA_URL}/api/health"
    local http_code
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "${GRAFANA_TIMEOUT}" \
        --max-time "${GRAFANA_TIMEOUT}" \
        "${url}" 2>/dev/null || echo "000")
    
    if [[ "${http_code}" == "200" ]]; then
        return 0
    else
        log_error "HTTP health check failed with code: ${http_code}"
        return 1
    fi
}

check_api_health() {
    local url="${GRAFANA_URL}/api/health"
    local response
    
    response=$(curl -s --connect-timeout "${GRAFANA_TIMEOUT}" \
        --max-time "${GRAFANA_TIMEOUT}" \
        "${url}" 2>/dev/null || echo "{}")
    
    # Parse JSON response
    local database=$(echo "${response}" | grep -o '"database":\s*"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    local version=$(echo "${response}" | grep -o '"version":\s*"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    
    if [[ "${database}" == "ok" ]]; then
        log_info "Grafana is healthy (version: ${version})"
        return 0
    else
        log_error "Grafana health check failed (database: ${database})"
        return 1
    fi
}

check_process() {
    if pgrep -x "grafana-server" > /dev/null; then
        log_info "Grafana server process is running"
        return 0
    else
        log_error "Grafana server process is not running"
        return 1
    fi
}

check_systemd_status() {
    if command -v systemctl &> /dev/null; then
        if systemctl is-active --quiet grafana-server; then
            log_info "Grafana systemd service is active"
            return 0
        else
            log_error "Grafana systemd service is not active"
            systemctl status grafana-server --no-pager || true
            return 1
        fi
    fi
    return 0
}

check_database_connection() {
    # This is a basic check through the API
    # More detailed checks would require direct database access
    local url="${GRAFANA_URL}/api/datasources"
    local http_code
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "${GRAFANA_TIMEOUT}" \
        --max-time "${GRAFANA_TIMEOUT}" \
        "${url}" 2>/dev/null || echo "000")
    
    if [[ "${http_code}" == "200" ]] || [[ "${http_code}" == "401" ]]; then
        # 401 is ok - means server is responding, just not authenticated
        log_info "Database connection appears healthy"
        return 0
    else
        log_error "Database connection check failed with code: ${http_code}"
        return 1
    fi
}

restart_grafana() {
    if [[ "${AUTO_RESTART}" != "true" ]]; then
        log_warn "Auto-restart is disabled. Manual intervention required."
        return 1
    fi
    
    log_warn "Attempting to restart Grafana..."
    
    if command -v systemctl &> /dev/null; then
        if sudo systemctl restart grafana-server; then
            log_info "Grafana restarted successfully via systemd"
            sleep 10  # Wait for service to start
            return 0
        else
            log_error "Failed to restart Grafana via systemd"
            return 1
        fi
    else
        log_error "systemctl not found. Cannot auto-restart Grafana"
        return 1
    fi
}

send_alert() {
    local message="$1"
    local severity="${2:-WARNING}"
    
    # Add your alerting mechanism here
    # Examples:
    # - Send email
    # - Post to Slack webhook
    # - Send to PagerDuty
    # - Write to syslog
    
    # Syslog example
    if command -v logger &> /dev/null; then
        logger -t grafana-healthcheck -p user.warning "${severity}: ${message}"
    fi
    
    # Email example (requires mail command)
    # if command -v mail &> /dev/null && [[ -n "${ALERT_EMAIL:-}" ]]; then
    #     echo "${message}" | mail -s "[${severity}] Grafana Health Alert" "${ALERT_EMAIL}"
    # fi
    
    log_warn "Alert sent: ${message}"
}

perform_health_check() {
    local retry_count=0
    local check_failed=false
    
    log_info "Starting Grafana health check..."
    
    # Check process first
    if ! check_process; then
        check_failed=true
    fi
    
    # Check systemd status
    if ! check_systemd_status; then
        check_failed=true
    fi
    
    # Try HTTP health check with retries
    while [[ ${retry_count} -lt ${MAX_RETRIES} ]]; do
        if check_http_health && check_api_health; then
            log_info "HTTP health check passed"
            
            # Additional checks
            check_database_connection
            
            log_info "All health checks passed successfully"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ ${retry_count} -lt ${MAX_RETRIES} ]]; then
            log_warn "Health check failed (attempt ${retry_count}/${MAX_RETRIES}), retrying in ${RETRY_DELAY}s..."
            sleep "${RETRY_DELAY}"
        fi
    done
    
    log_error "Health check failed after ${MAX_RETRIES} attempts"
    send_alert "Grafana health check failed after ${MAX_RETRIES} attempts"
    
    # Attempt restart if enabled
    if restart_grafana; then
        # Wait and check again
        sleep 15
        if check_http_health && check_api_health; then
            log_info "Grafana recovered after restart"
            send_alert "Grafana was automatically restarted and is now healthy" "INFO"
            return 0
        else
            log_error "Grafana still unhealthy after restart"
            send_alert "Grafana restart failed - manual intervention required" "CRITICAL"
            return 1
        fi
    fi
    
    return 1
}

print_usage() {
    cat << EOF
Grafana Health Check Script

Usage: $0 [OPTIONS]

Options:
    -u, --url URL           Grafana URL (default: http://localhost:3000)
    -t, --timeout SECONDS   Request timeout (default: 10)
    -r, --retries NUMBER    Max retry attempts (default: 3)
    -d, --delay SECONDS     Delay between retries (default: 5)
    -l, --log FILE         Log file location (default: /var/log/grafana-healthcheck.log)
    --no-restart           Disable automatic restart
    -h, --help             Show this help message

Environment Variables:
    GRAFANA_URL            Override default Grafana URL
    GRAFANA_TIMEOUT        Override default timeout
    MAX_RETRIES            Override max retries
    RETRY_DELAY            Override retry delay
    LOG_FILE               Override log file location
    AUTO_RESTART           Set to 'false' to disable auto-restart
    ALERT_EMAIL            Email address for alerts (requires mail command)

Examples:
    # Basic health check
    $0

    # Custom URL and timeout
    $0 -u http://grafana.example.com:3000 -t 5

    # Disable auto-restart
    $0 --no-restart

    # Check with custom retry settings
    $0 -r 5 -d 10

Cron Example:
    # Check every 5 minutes
    */5 * * * * /usr/local/bin/grafana-healthcheck.sh >> /var/log/grafana-healthcheck.log 2>&1
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            GRAFANA_URL="$2"
            shift 2
            ;;
        -t|--timeout)
            GRAFANA_TIMEOUT="$2"
            shift 2
            ;;
        -r|--retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        -d|--delay)
            RETRY_DELAY="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        --no-restart)
            AUTO_RESTART="false"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "========================================="
    log_info "Grafana Health Check Starting"
    log_info "URL: ${GRAFANA_URL}"
    log_info "Timeout: ${GRAFANA_TIMEOUT}s"
    log_info "Max Retries: ${MAX_RETRIES}"
    log_info "Auto-restart: ${AUTO_RESTART}"
    log_info "========================================="
    
    if perform_health_check; then
        log_info "Health check completed successfully"
        exit 0
    else
        log_error "Health check failed"
        exit 1
    fi
}

# Run main function
main
