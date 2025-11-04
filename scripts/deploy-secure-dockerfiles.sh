#!/bin/bash

# Deploy Security-Hardened Dockerfiles
# This script helps deploy and validate the security-hardened Dockerfiles

set -euo pipefail

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SERVICES=("ui" "catalog" "cart" "orders" "checkout")
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Deploy Security-Hardened Dockerfiles

Usage: $0 [OPTIONS] COMMAND

Commands:
    backup      Create backups of existing Dockerfiles
    deploy      Deploy security-hardened Dockerfiles
    validate    Validate deployed Dockerfiles
    rollback    Rollback to previous Dockerfiles
    test        Run security tests on images
    scan        Run vulnerability scans
    all         Run backup, deploy, validate, and scan

Options:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output
    -d, --dry-run   Show what would be done without executing
    -s, --service   Specify single service (ui|catalog|cart|orders|checkout)

Examples:
    $0 backup
    $0 deploy --service ui
    $0 validate --verbose
    $0 all
EOF
}

# Parse command line arguments
VERBOSE=false
DRY_RUN=false
SINGLE_SERVICE=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--service)
            SINGLE_SERVICE="$2"
            shift 2
            ;;
        backup|deploy|validate|rollback|test|scan|all)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$COMMAND" ]]; then
    log_error "No command specified"
    show_help
    exit 1
fi

# Set services to process
if [[ -n "$SINGLE_SERVICE" ]]; then
    if [[ " ${SERVICES[@]} " =~ " ${SINGLE_SERVICE} " ]]; then
        SERVICES=("$SINGLE_SERVICE")
    else
        log_error "Invalid service: $SINGLE_SERVICE"
        log_info "Valid services: ${SERVICES[*]}"
        exit 1
    fi
fi

# Backup existing Dockerfiles
backup_dockerfiles() {
    log_info "Creating backups of existing Dockerfiles..."
    
    for service in "${SERVICES[@]}"; do
        dockerfile_path="$PROJECT_ROOT/src/$service/Dockerfile"
        
        if [[ -f "$dockerfile_path" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would backup: $dockerfile_path -> ${dockerfile_path}${BACKUP_SUFFIX}"
            else
                cp "$dockerfile_path" "${dockerfile_path}${BACKUP_SUFFIX}"
                log_success "Backed up: $service/Dockerfile"
            fi
        else
            log_warning "Dockerfile not found for service: $service"
        fi
    done
}

# Deploy security-hardened Dockerfiles
deploy_dockerfiles() {
    log_info "Deploying security-hardened Dockerfiles..."
    
    for service in "${SERVICES[@]}"; do
        secure_dockerfile="$PROJECT_ROOT/src/$service/Dockerfile.secure"
        target_dockerfile="$PROJECT_ROOT/src/$service/Dockerfile"
        
        if [[ -f "$secure_dockerfile" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would deploy: $secure_dockerfile -> $target_dockerfile"
            else
                cp "$secure_dockerfile" "$target_dockerfile"
                log_success "Deployed: $service/Dockerfile.secure -> $service/Dockerfile"
            fi
        else
            log_error "Security-hardened Dockerfile not found: $secure_dockerfile"
            exit 1
        fi
    done
}

# Validate deployed Dockerfiles
validate_dockerfiles() {
    log_info "Validating deployed Dockerfiles..."
    
    for service in "${SERVICES[@]}"; do
        dockerfile_path="$PROJECT_ROOT/src/$service/Dockerfile"
        
        if [[ -f "$dockerfile_path" ]]; then
            log_info "Validating $service Dockerfile..."
            
            # Check for security improvements
            if grep -q "@sha256:" "$dockerfile_path"; then
                log_success "✓ $service: Base image SHA256 pinning found"
            else
                log_warning "✗ $service: Base image SHA256 pinning missing"
            fi
            
            if grep -q "HEALTHCHECK" "$dockerfile_path"; then
                log_success "✓ $service: Health check found"
            else
                log_warning "✗ $service: Health check missing"
            fi
            
            if grep -q "USER.*appuser" "$dockerfile_path"; then
                log_success "✓ $service: Non-root user found"
            else
                log_warning "✗ $service: Non-root user missing"
            fi
            
            if grep -q "security\." "$dockerfile_path"; then
                log_success "✓ $service: Security labels found"
            else
                log_warning "✗ $service: Security labels missing"
            fi
            
            # Validate Dockerfile syntax
            if [[ "$DRY_RUN" == "false" ]]; then
                if docker build --no-cache -f "$dockerfile_path" -t "validate-$service" "$PROJECT_ROOT/src/$service" > /dev/null 2>&1; then
                    log_success "✓ $service: Dockerfile builds successfully"
                    docker rmi "validate-$service" > /dev/null 2>&1 || true
                else
                    log_error "✗ $service: Dockerfile build failed"
                fi
            fi
        else
            log_error "Dockerfile not found: $dockerfile_path"
        fi
    done
}

# Rollback to previous Dockerfiles
rollback_dockerfiles() {
    log_info "Rolling back to previous Dockerfiles..."
    
    for service in "${SERVICES[@]}"; do
        dockerfile_path="$PROJECT_ROOT/src/$service/Dockerfile"
        
        # Find the most recent backup
        backup_file=$(find "$PROJECT_ROOT/src/$service/" -name "Dockerfile.backup.*" -type f | sort -r | head -n1)
        
        if [[ -n "$backup_file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would rollback: $backup_file -> $dockerfile_path"
            else
                cp "$backup_file" "$dockerfile_path"
                log_success "Rolled back: $service/Dockerfile"
            fi
        else
            log_warning "No backup found for service: $service"
        fi
    done
}

# Run security tests
test_dockerfiles() {
    log_info "Running security tests on Docker images..."
    
    for service in "${SERVICES[@]}"; do
        dockerfile_path="$PROJECT_ROOT/src/$service/Dockerfile"
        image_name="security-test-$service"
        
        if [[ -f "$dockerfile_path" ]]; then
            log_info "Testing $service..."
            
            if [[ "$DRY_RUN" == "false" ]]; then
                # Build image for testing
                if docker build -f "$dockerfile_path" -t "$image_name" "$PROJECT_ROOT/src/$service" > /dev/null 2>&1; then
                    
                    # Test non-root user
                    user_test=$(docker run --rm "$image_name" whoami 2>/dev/null || echo "root")
                    if [[ "$user_test" != "root" ]]; then
                        log_success "✓ $service: Running as non-root user ($user_test)"
                    else
                        log_error "✗ $service: Running as root user"
                    fi
                    
                    # Test health check (if container starts successfully)
                    if docker run -d --name "test-$service" "$image_name" > /dev/null 2>&1; then
                        sleep 5
                        health_status=$(docker inspect "test-$service" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
                        if [[ "$health_status" == "healthy" || "$health_status" == "starting" ]]; then
                            log_success "✓ $service: Health check working"
                        else
                            log_warning "? $service: Health check status: $health_status"
                        fi
                        docker rm -f "test-$service" > /dev/null 2>&1
                    fi
                    
                    # Clean up test image
                    docker rmi "$image_name" > /dev/null 2>&1
                else
                    log_error "✗ $service: Failed to build image for testing"
                fi
            else
                log_info "[DRY-RUN] Would test security for: $service"
            fi
        fi
    done
}

# Run vulnerability scans
scan_dockerfiles() {
    log_info "Running vulnerability scans..."
    
    # Check if Trivy is available
    if ! command -v trivy &> /dev/null; then
        log_warning "Trivy not found. Installing Trivy..."
        if command -v curl &> /dev/null; then
            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
        else
            log_error "Cannot install Trivy. Please install manually."
            return 1
        fi
    fi
    
    for service in "${SERVICES[@]}"; do
        dockerfile_path="$PROJECT_ROOT/src/$service/Dockerfile"
        image_name="scan-$service"
        
        if [[ -f "$dockerfile_path" ]]; then
            log_info "Scanning $service for vulnerabilities..."
            
            if [[ "$DRY_RUN" == "false" ]]; then
                # Build image for scanning
                if docker build -f "$dockerfile_path" -t "$image_name" "$PROJECT_ROOT/src/$service" > /dev/null 2>&1; then
                    
                    # Run Trivy scan
                    scan_output=$(trivy image --security-checks vuln --format table "$image_name" 2>/dev/null || echo "Scan failed")
                    
                    if [[ "$scan_output" != "Scan failed" ]]; then
                        if [[ "$VERBOSE" == "true" ]]; then
                            echo "$scan_output"
                        fi
                        
                        # Count critical and high vulnerabilities
                        critical_count=$(echo "$scan_output" | grep -c "CRITICAL" || echo "0")
                        high_count=$(echo "$scan_output" | grep -c "HIGH" || echo "0")
                        
                        if [[ "$critical_count" -eq 0 && "$high_count" -eq 0 ]]; then
                            log_success "✓ $service: No critical or high vulnerabilities found"
                        else
                            log_warning "! $service: Found $critical_count critical and $high_count high vulnerabilities"
                        fi
                    else
                        log_error "✗ $service: Vulnerability scan failed"
                    fi
                    
                    # Clean up scan image
                    docker rmi "$image_name" > /dev/null 2>&1
                else
                    log_error "✗ $service: Failed to build image for scanning"
                fi
            else
                log_info "[DRY-RUN] Would scan vulnerabilities for: $service"
            fi
        fi
    done
}

# Main execution
main() {
    log_info "Starting security deployment process..."
    log_info "Command: $COMMAND"
    log_info "Services: ${SERVICES[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN mode enabled - no changes will be made"
    fi
    
    case "$COMMAND" in
        backup)
            backup_dockerfiles
            ;;
        deploy)
            deploy_dockerfiles
            ;;
        validate)
            validate_dockerfiles
            ;;
        rollback)
            rollback_dockerfiles
            ;;
        test)
            test_dockerfiles
            ;;
        scan)
            scan_dockerfiles
            ;;
        all)
            backup_dockerfiles
            deploy_dockerfiles
            validate_dockerfiles
            scan_dockerfiles
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            exit 1
            ;;
    esac
    
    log_success "Security deployment process completed!"
}

# Run main function
main "$@"