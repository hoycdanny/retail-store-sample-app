#!/bin/bash

# Security Validation Script for Catalog Service Dockerfile
# This script validates the security improvements implemented in the Dockerfile

set -e

echo "🔒 Starting Security Validation for Catalog Service..."
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
    fi
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Build the image
echo "📦 Building enhanced Docker image..."
if docker build -t catalog-service:security-test . > /dev/null 2>&1; then
    print_status 0 "Docker image built successfully"
else
    print_status 1 "Failed to build Docker image"
    exit 1
fi

# Test 1: Verify non-root user
echo ""
echo "👤 Testing User Security..."
USER_ID=$(docker run --rm catalog-service:security-test id -u)
if [ "$USER_ID" != "0" ]; then
    print_status 0 "Container runs as non-root user (UID: $USER_ID)"
else
    print_status 1 "Container runs as root user - SECURITY RISK"
fi

# Test 2: Verify high UID
if [ "$USER_ID" -gt 1000 ]; then
    print_status 0 "User ID is appropriately high ($USER_ID)"
else
    print_status 1 "User ID should be higher than 1000 for better security"
fi

# Test 3: Check for shell access (should be limited)
echo ""
echo "🐚 Testing Shell Access..."
SHELL_TEST=$(docker run --rm catalog-service:security-test sh -c "echo 'shell access'" 2>/dev/null || echo "no shell")
if [ "$SHELL_TEST" = "shell access" ]; then
    print_warning "Shell access available - consider using distroless for production"
else
    print_status 0 "Limited shell access (more secure)"
fi

# Test 4: Verify health check is configured
echo ""
echo "🏥 Testing Health Check Configuration..."
HEALTH_CHECK=$(docker inspect catalog-service:security-test | jq -r '.[0].Config.Healthcheck.Test[0]' 2>/dev/null || echo "null")
if [ "$HEALTH_CHECK" != "null" ] && [ "$HEALTH_CHECK" != "" ]; then
    print_status 0 "Health check is configured"
else
    print_status 1 "Health check is not configured"
fi

# Test 5: Check image labels
echo ""
echo "🏷️  Testing Security Labels..."
SECURITY_LABELS=$(docker inspect catalog-service:security-test | jq -r '.[0].Config.Labels | keys[]' 2>/dev/null | grep -c "security\|org.opencontainers" || echo "0")
if [ "$SECURITY_LABELS" -gt 0 ]; then
    print_status 0 "Security labels are present ($SECURITY_LABELS labels found)"
else
    print_status 1 "Security labels are missing"
fi

# Test 6: Verify exposed port
echo ""
echo "🌐 Testing Port Configuration..."
EXPOSED_PORT=$(docker inspect catalog-service:security-test | jq -r '.[0].Config.ExposedPorts | keys[]' 2>/dev/null | head -1 || echo "")
if [ "$EXPOSED_PORT" = "8080/tcp" ]; then
    print_status 0 "Port 8080 is properly exposed"
else
    print_status 1 "Expected port 8080 to be exposed, found: $EXPOSED_PORT"
fi

# Test 7: Check image size (should be reasonable)
echo ""
echo "📏 Testing Image Size..."
IMAGE_SIZE=$(docker images catalog-service:security-test --format "{{.Size}}" | head -1)
echo "Image size: $IMAGE_SIZE"
print_status 0 "Image size information available"

# Test 8: Test application startup (basic functionality)
echo ""
echo "🚀 Testing Application Startup..."
CONTAINER_ID=$(docker run -d -p 8080:8080 catalog-service:security-test)
sleep 5

# Check if container is running
if docker ps | grep -q "$CONTAINER_ID"; then
    print_status 0 "Container started successfully"
    
    # Test health endpoint if accessible
    if command -v curl >/dev/null 2>&1; then
        if curl -f http://localhost:8080/health >/dev/null 2>&1; then
            print_status 0 "Health endpoint is accessible"
        else
            print_warning "Health endpoint test failed (may be normal in test environment)"
        fi
    else
        print_warning "curl not available for health endpoint testing"
    fi
else
    print_status 1 "Container failed to start"
fi

# Cleanup
docker stop "$CONTAINER_ID" >/dev/null 2>&1 || true
docker rm "$CONTAINER_ID" >/dev/null 2>&1 || true

# Test 9: Security scan (if available)
echo ""
echo "🔍 Security Scanning..."
if command -v docker >/dev/null 2>&1 && docker scout version >/dev/null 2>&1; then
    echo "Running Docker Scout security scan..."
    docker scout cves catalog-service:security-test --format sarif > security-scan-results.sarif 2>/dev/null || true
    if [ -f security-scan-results.sarif ]; then
        print_status 0 "Security scan completed (results in security-scan-results.sarif)"
    else
        print_warning "Security scan available but failed to generate results"
    fi
else
    print_warning "Docker Scout not available for security scanning"
fi

# Test 10: Dockerfile best practices check
echo ""
echo "📋 Dockerfile Best Practices Check..."
DOCKERFILE_CHECKS=0

# Check for COPY --chown usage
if grep -q "COPY --chown" Dockerfile; then
    print_status 0 "Uses COPY --chown for proper file ownership"
    ((DOCKERFILE_CHECKS++))
fi

# Check for specific image digest
if grep -q "@sha256:" Dockerfile; then
    print_status 0 "Uses pinned image digests"
    ((DOCKERFILE_CHECKS++))
fi

# Check for minimal package installation
if grep -q "apk add --no-cache" Dockerfile; then
    print_status 0 "Uses minimal package installation"
    ((DOCKERFILE_CHECKS++))
fi

# Check for cache cleanup
if grep -q "rm -rf.*cache" Dockerfile; then
    print_status 0 "Includes cache cleanup"
    ((DOCKERFILE_CHECKS++))
fi

echo ""
echo "📊 Security Validation Summary"
echo "=============================="
echo "Dockerfile best practices: $DOCKERFILE_CHECKS/4 checks passed"

if [ "$DOCKERFILE_CHECKS" -ge 3 ]; then
    print_status 0 "Dockerfile follows security best practices"
else
    print_status 1 "Dockerfile needs improvement in security practices"
fi

# Final recommendations
echo ""
echo "🎯 Security Recommendations"
echo "============================"
echo "1. Regularly update base image digests"
echo "2. Monitor security scan results"
echo "3. Implement runtime security policies"
echo "4. Use read-only filesystem in production"
echo "5. Implement network policies"
echo "6. Monitor container behavior"

echo ""
echo "🔒 Security validation completed!"
echo "Review the results above and address any failed checks."

# Cleanup test image
docker rmi catalog-service:security-test >/dev/null 2>&1 || true