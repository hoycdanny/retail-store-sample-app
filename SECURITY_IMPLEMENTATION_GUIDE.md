# Security Implementation Guide
## Retail Store Microservices Docker Security Hardening

### Overview

This guide provides step-by-step instructions for implementing the security improvements identified in the comprehensive security analysis. Each section includes specific code examples, configuration changes, and validation procedures.

## Table of Contents

1. [Pre-Implementation Checklist](#pre-implementation-checklist)
2. [Phase 1: Base Image Security](#phase-1-base-image-security)
3. [Phase 2: User Privilege Management](#phase-2-user-privilege-management)
4. [Phase 3: Secrets and Configuration Security](#phase-3-secrets-and-configuration-security)
5. [Phase 4: Health Monitoring Implementation](#phase-4-health-monitoring-implementation)
6. [Phase 5: Build Process Security](#phase-5-build-process-security)
7. [Phase 6: Runtime Security Hardening](#phase-6-runtime-security-hardening)
8. [CI/CD Integration](#cicd-integration)
9. [Validation and Testing](#validation-and-testing)
10. [Monitoring and Maintenance](#monitoring-and-maintenance)

## Pre-Implementation Checklist

### Environment Preparation
- [ ] Backup existing Dockerfiles
- [ ] Set up development environment for testing
- [ ] Verify Docker and container registry access
- [ ] Prepare staging environment for validation
- [ ] Set up security scanning tools (Trivy, etc.)

### Team Coordination
- [ ] Notify development teams of upcoming changes
- [ ] Schedule implementation windows
- [ ] Prepare rollback procedures
- [ ] Set up communication channels for issues

### Infrastructure Requirements
- [ ] Verify Kubernetes cluster security contexts
- [ ] Check container registry security policies
- [ ] Validate monitoring and alerting systems
- [ ] Confirm secrets management integration

## Phase 1: Base Image Security

### 1.1 SHA256 Pinning Implementation

**Objective**: Replace generic image tags with SHA256-pinned versions for reproducible builds.

#### Step 1: Identify Current Base Images
```bash
# Find all FROM statements in Dockerfiles
find src/ -name "Dockerfile*" -exec grep -H "FROM" {} \;
```

#### Step 2: Get SHA256 Hashes
```bash
# Get SHA256 for Amazon Linux 2023
docker pull public.ecr.aws/amazonlinux/amazonlinux:2023
docker inspect public.ecr.aws/amazonlinux/amazonlinux:2023 | grep -A1 "RepoDigests"

# Get SHA256 for Node.js Alpine
docker pull node:20.11.0-alpine
docker inspect node:20.11.0-alpine | grep -A1 "RepoDigests"
```

#### Step 3: Update Dockerfiles
Replace all FROM statements with SHA256-pinned versions:

```dockerfile
# Before
FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# After
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.3.20240117.0@sha256:34d8b8d8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b
```

### 1.2 Base Image Vulnerability Scanning

#### Step 1: Integrate Trivy Scanning
```bash
# Add to CI/CD pipeline
trivy image --security-checks vuln --format json --output scan-results.json <image-name>
```

#### Step 2: Set Vulnerability Thresholds
```yaml
# .github/workflows/security-scan.yml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE_NAME }}
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'
```

## Phase 2: User Privilege Management

### 2.1 Non-Root User Implementation

**Objective**: Ensure all containers run as non-root users with minimal privileges.

#### Step 1: Standardize User Creation
```dockerfile
# Enhanced user creation pattern
ENV APPUSER=appuser
ENV APPUID=1000
ENV APPGID=1000

RUN groupadd -r -g "$APPGID" "$APPUSER" && \
    useradd -r -g "$APPUSER" -u "$APPUID" \
    --home "/app" \
    --create-home \
    --shell /sbin/nologin \
    "$APPUSER"
```

#### Step 2: Fix Checkout Service User Inconsistency
```dockerfile
# Before (Inconsistent)
COPY --chown=node:node --from=build /usr/src/app/node_modules ./node_modules
COPY --chown=node:node --from=build /usr/src/app/dist ./dist

# After (Consistent)
COPY --chown=appuser:appuser --from=build /usr/src/app/node_modules ./node_modules
COPY --chown=appuser:appuser --from=build /usr/src/app/dist ./dist
```

### 2.2 File Permission Hardening

#### Step 1: Implement Explicit Permissions
```dockerfile
# Set file permissions explicitly
RUN chmod 444 ./ATTRIBUTION.md ./LICENSES.md && \
    chmod 544 ./app.jar
```

#### Step 2: Validate Permissions
```bash
# Test script to validate file permissions
docker run --rm <image-name> ls -la /app/
```

## Phase 3: Secrets and Configuration Security

### 3.1 Environment Variable Security

**Objective**: Secure environment variable handling and eliminate JAVA_OPTS exposure.

#### Step 1: Replace JAVA_OPTS with Secure Alternatives
```dockerfile
# Before (Vulnerable)
ENV JAVA_TOOL_OPTIONS=
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]

# After (Secure)
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

#### Step 2: Implement Secrets Scanning
```bash
# Add to CI/CD pipeline
docker run --rm -v $(pwd):/src trufflesecurity/trufflehog:latest filesystem /src --json
```

### 3.2 Build-Time Secret Management

#### Step 1: Use Multi-Stage Builds for Secrets
```dockerfile
# Build stage with secrets
FROM base-image AS build-with-secrets
ARG BUILD_SECRET
RUN --mount=type=secret,id=build-secret \
    echo "Using secret for build" && \
    # Build operations using secret
    rm -rf /tmp/secrets

# Runtime stage without secrets
FROM base-image AS runtime
COPY --from=build-with-secrets /app/binary /app/
```

## Phase 4: Health Monitoring Implementation

### 4.1 Health Check Implementation

**Objective**: Add comprehensive health checks to all services.

#### Step 1: Java Services Health Checks
```dockerfile
# Spring Boot services
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1
```

#### Step 2: Go Service Health Checks
```dockerfile
# Go services (requires health endpoint implementation)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /app/catalog --health-check || exit 1
```

#### Step 3: Node.js Service Health Checks
```dockerfile
# Node.js services
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
```

### 4.2 Application Health Endpoint Implementation

#### Step 1: Spring Boot Health Endpoints
```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health
  endpoint:
    health:
      show-details: when-authorized
```

#### Step 2: Go Health Endpoint
```go
// Add to main.go
func healthCheck() {
    if len(os.Args) > 1 && os.Args[1] == "--health-check" {
        // Perform health check logic
        os.Exit(0)
    }
}
```

#### Step 3: Node.js Health Endpoint
```typescript
// Add to app.controller.ts
@Get('health')
getHealth(): object {
  return { status: 'ok', timestamp: new Date().toISOString() };
}
```

## Phase 5: Build Process Security

### 5.1 Dependency Management Security

**Objective**: Secure dependency management and minimize build-time attack surface.

#### Step 1: Remove Unnecessary Build Dependencies
```dockerfile
# Before (Catalog service)
RUN dnf install -y git golang

# After (Minimal dependencies)
RUN dnf install -y golang
```

#### Step 2: Implement Dependency Verification
```dockerfile
# Go services - verify dependencies
RUN go mod download && go mod verify

# Java services - verify checksums
RUN ./mvnw dependency:go-offline -B -q

# Node.js services - use frozen lockfile
RUN yarn install --frozen-lockfile
```

### 5.2 Build Cache Security

#### Step 1: Secure Build Cache
```dockerfile
# Clear build caches and temporary files
RUN dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/* /var/log/dnf*
```

#### Step 2: Multi-Stage Build Optimization
```dockerfile
# Separate build and runtime stages
FROM base AS build-env
# Build operations

FROM base AS runtime
COPY --from=build-env /app/binary /app/
# No build tools in runtime image
```

## Phase 6: Runtime Security Hardening

### 6.1 Container Security Labels

**Objective**: Add security metadata for monitoring and compliance.

#### Step 1: Implement Security Labels
```dockerfile
LABEL maintainer="security-team@company.com" \
      version="1.0.0" \
      description="Security-hardened service" \
      security.scan="enabled" \
      security.non-root="true" \
      security.health-check="enabled"
```

### 6.2 Shell Injection Prevention

#### Step 1: Use Exec Form for ENTRYPOINT
```dockerfile
# Before (Shell form - vulnerable)
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]

# After (Exec form - secure)
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

## CI/CD Integration

### Security Pipeline Integration

#### Step 1: Update CI/CD Pipeline
```yaml
# .github/workflows/security-pipeline.yml
name: Security Pipeline
on: [push, pull_request]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build security-hardened images
        run: |
          for service in ui catalog cart orders checkout; do
            docker build -f src/$service/Dockerfile.secure -t $service:secure src/$service/
          done
      
      - name: Run Trivy vulnerability scanner
        run: |
          for service in ui catalog cart orders checkout; do
            trivy image --security-checks vuln $service:secure
          done
      
      - name: Run secrets scanning
        run: |
          trufflehog filesystem . --json
```

### Deployment Automation

#### Step 1: Automated Deployment Script
```bash
#!/bin/bash
# deploy-secure-images.sh

set -euo pipefail

SERVICES=("ui" "catalog" "cart" "orders" "checkout")
ENVIRONMENT=${1:-development}

for service in "${SERVICES[@]}"; do
    echo "Deploying secure $service to $ENVIRONMENT"
    
    # Build secure image
    docker build -f src/$service/Dockerfile.secure -t $service:secure src/$service/
    
    # Run security scan
    trivy image --security-checks vuln $service:secure
    
    # Deploy if scan passes
    kubectl set image deployment/$service $service=$service:secure -n $ENVIRONMENT
done
```

## Validation and Testing

### Security Validation Checklist

#### Container Security Tests
```bash
# Test non-root user
docker run --rm <image> whoami | grep -v root

# Test file permissions
docker run --rm <image> ls -la /app/

# Test health check
docker run -d --name test-container <image>
docker exec test-container curl -f http://localhost:8080/health

# Test resource limits
docker run --rm --memory=100m --cpus=0.5 <image>
```

### Performance Impact Assessment

#### Step 1: Baseline Performance Metrics
```bash
# Measure startup time
time docker run --rm <image> echo "Container started"

# Measure memory usage
docker stats --no-stream <container-id>

# Measure image size
docker images <image> --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
```

## Monitoring and Maintenance

### Security Monitoring Setup

#### Step 1: Container Security Monitoring
```yaml
# monitoring/security-alerts.yml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: container-security-alerts
spec:
  groups:
  - name: container.security
    rules:
    - alert: ContainerRunningAsRoot
      expr: container_spec_user == 0
      labels:
        severity: critical
      annotations:
        summary: "Container running as root user"
```

### Regular Maintenance Tasks

#### Weekly Tasks
- [ ] Review vulnerability scan results
- [ ] Update base image SHA256 hashes if needed
- [ ] Check health check success rates
- [ ] Review security incident logs

#### Monthly Tasks
- [ ] Comprehensive security assessment
- [ ] Update security documentation
- [ ] Review and update security policies
- [ ] Conduct security training sessions

#### Quarterly Tasks
- [ ] Full security audit
- [ ] Compliance assessment
- [ ] Security architecture review
- [ ] Update incident response procedures

---

This implementation guide provides comprehensive instructions for securing all microservice Dockerfiles in the retail-store application. Follow each phase systematically, validate changes thoroughly, and maintain ongoing security monitoring for optimal protection.