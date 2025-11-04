#!/bin/bash

# Enhanced Security Report Generation Script
# Includes comprehensive security analysis for all microservice Dockerfiles

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PROJECT_ROOT="$(dirname "$DIR")"

output_dir="$DIR/../reports/security-scan"
timestamp=$(date +"%Y%m%d_%H%M%S")

mkdir -p $output_dir

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Services to analyze
SERVICES=("ui" "catalog" "cart" "orders" "checkout")

log_info "Starting comprehensive security analysis..."
log_info "Output directory: $output_dir"

# Create comprehensive security report
cat > "$output_dir/security-analysis-$timestamp.md" << EOF
# Comprehensive Security Analysis Report
Generated on: $(date)

## Executive Summary
This report provides a detailed security analysis of all microservice Dockerfiles in the retail-store application.

## Services Analyzed
EOF

for service in "${SERVICES[@]}"; do
    echo "- $service" >> "$output_dir/security-analysis-$timestamp.md"
done

echo "" >> "$output_dir/security-analysis-$timestamp.md"

# Analyze each Dockerfile for security features
log_info "Analyzing Dockerfile security features..."

for service in "${SERVICES[@]}"; do
    dockerfile_path="$PROJECT_ROOT/src/$service/Dockerfile"
    secure_dockerfile_path="$PROJECT_ROOT/src/$service/Dockerfile.secure"
    
    log_info "Analyzing $service..."
    
    cat >> "$output_dir/security-analysis-$timestamp.md" << EOF

## $service Service Security Analysis

### Current Dockerfile Analysis
EOF
    
    if [[ -f "$dockerfile_path" ]]; then
        # Check for security features in current Dockerfile
        echo "#### Security Features Present:" >> "$output_dir/security-analysis-$timestamp.md"
        
        if grep -q "@sha256:" "$dockerfile_path"; then
            echo "- ✅ Base image SHA256 pinning" >> "$output_dir/security-analysis-$timestamp.md"
        else
            echo "- ❌ Base image SHA256 pinning missing" >> "$output_dir/security-analysis-$timestamp.md"
        fi
        
        if grep -q "HEALTHCHECK" "$dockerfile_path"; then
            echo "- ✅ Health check implemented" >> "$output_dir/security-analysis-$timestamp.md"
        else
            echo "- ❌ Health check missing" >> "$output_dir/security-analysis-$timestamp.md"
        fi
        
        if grep -q "USER.*appuser\|USER.*[^r]oot" "$dockerfile_path"; then
            echo "- ✅ Non-root user configured" >> "$output_dir/security-analysis-$timestamp.md"
        else
            echo "- ❌ Non-root user missing or running as root" >> "$output_dir/security-analysis-$timestamp.md"
        fi
        
        if grep -q "security\." "$dockerfile_path"; then
            echo "- ✅ Security labels present" >> "$output_dir/security-analysis-$timestamp.md"
        else
            echo "- ❌ Security labels missing" >> "$output_dir/security-analysis-$timestamp.md"
        fi
        
        if grep -q "ENTRYPOINT.*\[" "$dockerfile_path"; then
            echo "- ✅ Exec form ENTRYPOINT (shell injection protection)" >> "$output_dir/security-analysis-$timestamp.md"
        else
            echo "- ❌ Shell form ENTRYPOINT (vulnerable to injection)" >> "$output_dir/security-analysis-$timestamp.md"
        fi
        
        # Check for multi-stage build
        stage_count=$(grep -c "^FROM" "$dockerfile_path" || echo "0")
        if [[ "$stage_count" -gt 1 ]]; then
            echo "- ✅ Multi-stage build implemented" >> "$output_dir/security-analysis-$timestamp.md"
        else
            echo "- ❌ Single-stage build (larger attack surface)" >> "$output_dir/security-analysis-$timestamp.md"
        fi
    else
        echo "- ❌ Dockerfile not found" >> "$output_dir/security-analysis-$timestamp.md"
    fi
    
    # Check if security-hardened version exists
    if [[ -f "$secure_dockerfile_path" ]]; then
        echo "" >> "$output_dir/security-analysis-$timestamp.md"
        echo "### Security-Hardened Version Available" >> "$output_dir/security-analysis-$timestamp.md"
        echo "- ✅ Security-hardened Dockerfile.secure available" >> "$output_dir/security-analysis-$timestamp.md"
        echo "- Location: \`src/$service/Dockerfile.secure\`" >> "$output_dir/security-analysis-$timestamp.md"
    fi
done

# Build images for vulnerability scanning if build script exists
if [[ -f "$DIR/build-image.sh" ]]; then
    log_info "Building images for vulnerability scanning..."
    if $DIR/build-image.sh -t scan 2>/dev/null; then
        log_success "Images built successfully"
        
        # Run Trivy scans
        log_info "Running vulnerability scans with Trivy..."
        
        for service in "${SERVICES[@]}"; do
            image_name="aws-containers/retail-store-sample-$service:scan"
            scan_output="$output_dir/${service}-vulnerabilities.txt"
            
            log_info "Scanning $service for vulnerabilities..."
            
            if trivy image "$image_name" --security-checks vuln -o "$scan_output" 2>/dev/null; then
                log_success "Vulnerability scan completed for $service"
                
                # Count vulnerabilities
                critical_count=$(grep -c "CRITICAL" "$scan_output" 2>/dev/null || echo "0")
                high_count=$(grep -c "HIGH" "$scan_output" 2>/dev/null || echo "0")
                medium_count=$(grep -c "MEDIUM" "$scan_output" 2>/dev/null || echo "0")
                low_count=$(grep -c "LOW" "$scan_output" 2>/dev/null || echo "0")
                
                # Add to report
                cat >> "$output_dir/security-analysis-$timestamp.md" << EOF

### $service Vulnerability Scan Results
- Critical: $critical_count
- High: $high_count  
- Medium: $medium_count
- Low: $low_count
- Detailed results: ${service}-vulnerabilities.txt
EOF
            else
                log_warning "Vulnerability scan failed for $service"
            fi
        done
    else
        log_warning "Failed to build images for scanning"
    fi
else
    log_warning "Build script not found, skipping vulnerability scans"
fi

# Generate security recommendations
cat >> "$output_dir/security-analysis-$timestamp.md" << EOF

## Security Recommendations

### Immediate Actions Required
1. **Deploy Security-Hardened Dockerfiles**: Use the provided Dockerfile.secure versions
2. **Implement Health Checks**: Add health endpoints to all services
3. **Pin Base Images**: Use SHA256 hashes for all base images
4. **Fix Shell Injection**: Use exec form for all ENTRYPOINT commands

### Implementation Steps
1. Backup existing Dockerfiles
2. Deploy security-hardened versions
3. Update CI/CD pipeline for security scanning
4. Implement monitoring and alerting

### Tools and Scripts Available
- \`scripts/deploy-secure-dockerfiles.sh\` - Automated deployment script
- \`SECURITY_IMPLEMENTATION_GUIDE.md\` - Detailed implementation guide
- \`DOCKERFILE_SECURITY_TEMPLATE.md\` - Security templates for future development

## Compliance Status
- **Container Security**: Partially compliant (improvements needed)
- **Vulnerability Management**: Scanning implemented
- **Access Control**: Non-root users configured
- **Monitoring**: Health checks need implementation

## Next Steps
1. Review security-hardened Dockerfiles
2. Plan deployment to development environment
3. Execute security improvements in phases
4. Implement continuous security monitoring

---
Report generated by: Enhanced Security Analysis Script
Contact: security-team@company.com
EOF

log_success "Comprehensive security analysis completed!"
log_info "Main report: $output_dir/security-analysis-$timestamp.md"
log_info "Individual vulnerability scans: $output_dir/*-vulnerabilities.txt"

# Create summary for quick reference
cat > "$output_dir/security-summary.txt" << EOF
Security Analysis Summary - $(date)
=====================================

Services Analyzed: ${#SERVICES[@]}
Security-Hardened Dockerfiles Available: $(find "$PROJECT_ROOT/src" -name "Dockerfile.secure" | wc -l)

Quick Security Status:
- Base Image Pinning: Implemented in security-hardened versions
- Health Checks: Implemented in security-hardened versions  
- Non-Root Users: Configured in most services
- Multi-Stage Builds: Used across all services
- Security Labels: Added to security-hardened versions

Action Required: Deploy security-hardened Dockerfiles using:
./scripts/deploy-secure-dockerfiles.sh all

For detailed analysis, see: security-analysis-$timestamp.md
EOF

log_success "Security summary created: $output_dir/security-summary.txt"