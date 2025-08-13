#!/bin/bash
set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Mediabox Comprehensive Health Check Script
# Monitors overall system health including containers, connectivity, disk usage, and logs
# Provides quick overview and early problem detection for troubleshooting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$SCRIPT_DIR/health_check_$(date '+%Y%m%d').log"

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Status indicator functions
status_ok() {
    echo -e "${GREEN}✅ $1${NC}"
    log_message "INFO" "OK: $1"
}

status_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log_message "WARN" "$1"
}

status_error() {
    echo -e "${RED}❌ $1${NC}"
    log_message "ERROR" "$1"
}

status_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log_message "INFO" "$1"
}

# Header
print_header() {
    echo ""
    echo "==================================================================================="
    echo "                           🏥 MEDIABOX HEALTH CHECK                               "
    echo "==================================================================================="
    echo "Date: $(date)"
    echo "Host: $(hostname)"
    echo "Working Directory: $COMPOSE_DIR"
    echo "Log File: $LOG_FILE"
    echo "==================================================================================="
    echo ""
    
    log_message "INFO" "Health check started"
    log_message "INFO" "Host: $(hostname), Directory: $COMPOSE_DIR"
}

# Check if Docker and docker-compose are available
check_docker_availability() {
    echo "🐳 Docker System Check"
    echo "-----------------------------------------------------------------"
    
    if ! command -v docker >/dev/null 2>&1; then
        status_error "Docker not installed or not in PATH"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        status_error "Docker daemon not running"
        return 1
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        status_error "docker-compose not installed or not in PATH" 
        return 1
    fi
    
    status_ok "Docker system available"
    echo ""
}

# Container status check
check_container_status() {
    echo "📦 Container Status Check"
    echo "-----------------------------------------------------------------"
    
    cd "$COMPOSE_DIR" || {
        status_error "Cannot change to compose directory: $COMPOSE_DIR"
        return 1
    }
    
    if [[ ! -f "docker-compose.yml" ]]; then
        status_error "docker-compose.yml not found in $COMPOSE_DIR"
        return 1
    fi
    
    local containers_output
    if ! containers_output=$(docker-compose ps --format "table {{.Name}}\t{{.State}}\t{{.Ports}}" 2>/dev/null); then
        status_error "Failed to get container status"
        return 1
    fi
    
    echo "$containers_output"
    echo ""
    
    # Count running vs stopped containers
    local running_count stopped_count
    running_count=$(docker-compose ps -q | xargs -r docker inspect --format '{{.State.Status}}' 2>/dev/null | grep -c "running" || echo 0)
    stopped_count=$(docker-compose ps -q | xargs -r docker inspect --format '{{.State.Status}}' 2>/dev/null | grep -c -v "running" || echo 0)
    
    if [[ $running_count -gt 0 && $stopped_count -eq 0 ]]; then
        status_ok "All $running_count containers are running"
    elif [[ $running_count -gt 0 && $stopped_count -gt 0 ]]; then
        status_warning "$running_count containers running, $stopped_count containers stopped"
    else
        status_error "No containers are running"
    fi
    
    echo ""
}

# Service connectivity check
check_service_connectivity() {
    echo "🌐 Service Connectivity Check"
    echo "-----------------------------------------------------------------"
    
    # Define services with their ports (based on docker-compose.yml)
    declare -A services
    services["homer"]="80"
    services["sonarr"]="8989"
    services["radarr"]="7878" 
    services["lidarr"]="8686"
    services["prowlarr"]="9696"
    services["overseerr"]="5055"
    services["nzbget"]="6790"
    services["tautulli"]="8181"
    services["portainer"]="9443"
    services["delugevpn"]="8112"
    services["plex"]="32400"
    services["maintainerr"]="6246"
    
    local healthy_services=0
    local total_services=${#services[@]}
    
    for service_name in "${!services[@]}"; do
        local port="${services[$service_name]}"
        
        if timeout 5 bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
            status_ok "$service_name (port $port) - responding"
            ((healthy_services++))
        else
            status_error "$service_name (port $port) - not responding"
        fi
    done
    
    echo ""
    status_info "Service connectivity: $healthy_services/$total_services services responding"
    echo ""
}

# Disk usage check
check_disk_usage() {
    echo "💾 Disk Usage Check"
    echo "-----------------------------------------------------------------"
    
    # Check root filesystem
    local root_usage
    root_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ $root_usage -gt 90 ]]; then
        status_error "Root filesystem usage: ${root_usage}% (Critical)"
    elif [[ $root_usage -gt 80 ]]; then
        status_warning "Root filesystem usage: ${root_usage}% (High)"
    else
        status_ok "Root filesystem usage: ${root_usage}% (Normal)"
    fi
    
    # Check mediabox directory usage
    if [[ -d "$COMPOSE_DIR" ]]; then
        local mediabox_size
        mediabox_size=$(du -sh "$COMPOSE_DIR" 2>/dev/null | cut -f1)
        status_info "Mediabox directory size: $mediabox_size"
    fi
    
    # Check for large log files in scripts directory
    if [[ -d "$SCRIPT_DIR" ]]; then
        local log_files
        log_files=$(find "$SCRIPT_DIR" -name "*.log" -o -name "*.log.gz" 2>/dev/null | wc -l)
        if [[ $log_files -gt 0 ]]; then
            local log_size
            log_size=$(du -sh "$SCRIPT_DIR"/*.log "$SCRIPT_DIR"/*.log.gz 2>/dev/null | awk '{sum += $1} END {print sum "M"}' || echo "0M")
            status_info "Log files: $log_files files, total size: $log_size"
        else
            status_info "No log files found in scripts directory"
        fi
    fi
    
    echo ""
}

# Recent log activity check
check_log_activity() {
    echo "📋 Recent Log Activity Check"
    echo "-----------------------------------------------------------------"
    
    # Check for recent import logs
    local recent_import_logs
    recent_import_logs=$(find "$SCRIPT_DIR" -name "import_*.log" -mtime -1 2>/dev/null | wc -l)
    if [[ $recent_import_logs -gt 0 ]]; then
        status_ok "Recent import activity: $recent_import_logs log files from last 24h"
    else
        status_info "No recent import activity detected"
    fi
    
    # Check for recent media update logs
    local recent_media_logs  
    recent_media_logs=$(find "$SCRIPT_DIR" -name "media_update_*.log" -mtime -1 2>/dev/null | wc -l)
    if [[ $recent_media_logs -gt 0 ]]; then
        status_ok "Recent media processing: $recent_media_logs log files from last 24h"
    else
        status_info "No recent media processing detected"
    fi
    
    # Check container logs for errors
    cd "$COMPOSE_DIR" || return 1
    local containers_with_errors=0
    
    # Get list of running containers
    local running_containers
    running_containers=$(docker-compose ps -q 2>/dev/null)
    
    if [[ -n "$running_containers" ]]; then
        for container_id in $running_containers; do
            local container_name
            container_name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\//' || echo "unknown")
            
            # Check for recent errors (last hour)
            local error_count
            error_count=$(docker logs --since 1h "$container_id" 2>&1 | grep -i -c "error\|fail\|exception" 2>/dev/null || echo 0)
            
            if [[ $error_count -gt 10 ]]; then
                status_warning "$container_name: $error_count errors in last hour"
                ((containers_with_errors++))
            fi
        done
        
        if [[ $containers_with_errors -eq 0 ]]; then
            status_ok "No excessive errors detected in container logs"
        fi
    fi
    
    echo ""
}

# Configuration validity check
check_configuration_validity() {
    echo "⚙️  Configuration Validity Check"
    echo "-----------------------------------------------------------------"
    
    cd "$COMPOSE_DIR" || return 1
    
    # Validate docker-compose.yml syntax
    if docker-compose config >/dev/null 2>&1; then
        status_ok "docker-compose.yml syntax is valid"
    else
        status_error "docker-compose.yml syntax validation failed"
    fi
    
    # Check for .env file
    if [[ -f ".env" ]]; then
        status_ok ".env configuration file exists"
        
        # Check for critical environment variables
        local env_vars=("PUID" "PGID" "TZ" "IP_ADDRESS")
        for var in "${env_vars[@]}"; do
            if grep -q "^${var}=" ".env" 2>/dev/null; then
                status_ok "Environment variable $var is configured"
            else
                status_warning "Environment variable $var not found in .env"
            fi
        done
    else
        status_warning ".env configuration file not found"
    fi
    
    # Check for mediabox configuration
    if [[ -f "$SCRIPT_DIR/mediabox_config.json" ]]; then
        if python3 -m json.tool "$SCRIPT_DIR/mediabox_config.json" >/dev/null 2>&1; then
            status_ok "mediabox_config.json is valid JSON"
        else
            status_error "mediabox_config.json has invalid JSON syntax"
        fi
    else
        status_info "mediabox_config.json not found (may not be configured yet)"
    fi
    
    # Check scripts permissions
    local script_files=("import.sh" "rotate-logs.sh" "setup-secure-env.sh")
    for script in "${script_files[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            if [[ -x "$SCRIPT_DIR/$script" ]]; then
                status_ok "$script is executable"
            else
                status_warning "$script exists but is not executable"
            fi
        fi
    done
    
    echo ""
}

# System resources check
check_system_resources() {
    echo "🖥️  System Resources Check"  
    echo "-----------------------------------------------------------------"
    
    # Memory usage
    if command -v free >/dev/null 2>&1; then
        local mem_usage
        mem_usage=$(free | awk '/^Mem:/ {printf "%.1f", ($3/$2)*100}')
        if (( $(echo "$mem_usage > 90" | bc -l 2>/dev/null || echo 0) )); then
            status_error "Memory usage: ${mem_usage}% (Critical)"
        elif (( $(echo "$mem_usage > 80" | bc -l 2>/dev/null || echo 0) )); then
            status_warning "Memory usage: ${mem_usage}% (High)"  
        else
            status_ok "Memory usage: ${mem_usage}% (Normal)"
        fi
    fi
    
    # Load average
    if [[ -f /proc/loadavg ]]; then
        local load_avg
        load_avg=$(cut -d' ' -f1 /proc/loadavg)
        local cpu_count
        cpu_count=$(nproc)
        local load_percent
        load_percent=$(echo "scale=1; $load_avg * 100 / $cpu_count" | bc 2>/dev/null || echo 0)
        
        status_info "Load average: $load_avg (${load_percent}% of $cpu_count CPUs)"
    fi
    
    echo ""
}

# Summary and recommendations
print_summary() {
    echo "📊 Health Check Summary"
    echo "-----------------------------------------------------------------"
    
    local warning_count error_count
    warning_count=$(grep -c "WARN" "$LOG_FILE" 2>/dev/null || echo 0)
    error_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo 0)
    
    if [[ $error_count -eq 0 && $warning_count -eq 0 ]]; then
        status_ok "System health: EXCELLENT - No issues detected"
    elif [[ $error_count -eq 0 && $warning_count -gt 0 ]]; then
        status_warning "System health: GOOD - $warning_count warnings detected"
    else
        status_error "System health: ISSUES DETECTED - $error_count errors, $warning_count warnings"
    fi
    
    echo ""
    echo "💡 Recommendations:"
    
    if [[ $error_count -gt 0 ]]; then
        echo "   • Check container logs: docker-compose logs [service-name]"
        echo "   • Restart failed services: docker-compose restart [service-name]"
    fi
    
    if [[ $warning_count -gt 0 ]]; then
        echo "   • Review warnings in log file: $LOG_FILE"
        echo "   • Consider running maintenance scripts in scripts/ directory"
    fi
    
    echo "   • View detailed logs: tail -f $LOG_FILE"
    echo "   • Monitor resources: watch -n 5 docker stats"
    echo "   • Schedule regular health checks via cron"
    
    echo ""
    echo "==================================================================================="
    echo "Health check completed at $(date)"
    echo "Full log available at: $LOG_FILE"
    echo "==================================================================================="
    echo ""
    
    log_message "INFO" "Health check completed with $error_count errors and $warning_count warnings"
}

# Main execution
main() {
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
    
    print_header
    
    # Run all health checks
    check_docker_availability || exit 1
    check_container_status
    check_service_connectivity  
    check_disk_usage
    check_log_activity
    check_configuration_validity
    check_system_resources
    print_summary
    
    # Exit with appropriate code
    local error_count
    error_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo 0)
    exit "$((error_count > 0 ? 1 : 0))"
}

# Handle script arguments
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Mediabox Health Check Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --help, -h    Show this help message"
    echo "  --quiet, -q   Suppress colored output (for cron/automation)"
    echo ""
    echo "This script performs comprehensive health checks including:"
    echo "  • Container status and health"
    echo "  • Service connectivity testing"
    echo "  • Disk usage monitoring"
    echo "  • Recent log activity analysis"
    echo "  • Configuration file validation"
    echo "  • System resource monitoring"
    echo ""
    echo "Exit codes:"
    echo "  0 = All checks passed"  
    echo "  1 = Errors detected"
    echo ""
    exit 0
fi

# Handle quiet mode
if [[ "${1:-}" == "--quiet" || "${1:-}" == "-q" ]]; then
    # Disable colors for automation/cron usage
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

# Run main function
main "$@"