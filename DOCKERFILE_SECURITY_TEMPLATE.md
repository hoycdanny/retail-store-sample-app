# Dockerfile Security Best Practices Template

## Overview
This template provides security-hardened Dockerfile patterns for different technology stacks used in the retail-store application. Use these templates as starting points for creating secure container images.

## General Security Principles

### 1. Base Image Security
- Always pin base images with SHA256 hashes
- Use minimal base images (Alpine, distroless, or slim variants)
- Regularly update base images and scan for vulnerabilities
- Use official images from trusted registries

### 2. User Privilege Management
- Never run containers as root in production
- Create dedicated non-root users with minimal privileges
- Use consistent UID/GID across environments
- Disable shell access for application users

### 3. Build Process Security
- Use multi-stage builds to minimize final image size
- Remove build dependencies from runtime images
- Verify dependency integrity during build
- Clean up temporary files and caches

### 4. Runtime Security
- Implement health checks for all services
- Use exec form for ENTRYPOINT to prevent shell injection
- Set explicit file permissions
- Add security labels for monitoring

## Java/Spring Boot Template

```dockerfile
# Security-Hardened Java/Spring Boot Dockerfile Template
# Build Stage
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.3.20240117.0@sha256:ACTUAL_SHA256_HASH AS build-env

# Security: Install only essential build packages
RUN dnf --setopt=install_weak_deps=False install -q -y \
    maven \
    java-21-amazon-corretto-headless \
    which \
    tar \
    gzip \
    && \
    dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/*

# Security: Create non-root build user
RUN groupadd -r builduser && useradd -r -g builduser builduser
USER builduser

WORKDIR /home/builduser

# Security: Copy dependency files first for better caching
COPY --chown=builduser:builduser .mvn .mvn
COPY --chown=builduser:builduser mvnw .
COPY --chown=builduser:builduser pom.xml .

# Security: Download dependencies offline for reproducible builds
RUN ./mvnw dependency:go-offline -B -q

# Security: Copy source and build
COPY --chown=builduser:builduser ./src ./src
RUN ./mvnw -DskipTests package -q && \
    mv /home/builduser/target/*.jar /home/builduser/app.jar && \
    chmod 644 /home/builduser/app.jar

# Runtime Stage
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.3.20240117.0@sha256:ACTUAL_SHA256_HASH

# Security: Install minimal runtime dependencies
RUN dnf --setopt=install_weak_deps=False install -q -y \
    java-21-amazon-corretto-headless \
    shadow-utils \
    curl \
    && \
    dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/* /var/log/dnf*

# Security: Create non-root user with minimal privileges
ENV APPUSER=appuser
ENV APPUID=1000
ENV APPGID=1000

RUN groupadd -r -g "$APPGID" "$APPUSER" && \
    useradd -r -g "$APPUSER" -u "$APPUID" \
    --home "/app" \
    --create-home \
    --shell /sbin/nologin \
    "$APPUSER"

# Security: Set secure JVM options
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"
ENV SPRING_PROFILES_ACTIVE=prod
ENV SERVER_PORT=8080

WORKDIR /app
USER appuser

# Security: Copy files with proper ownership and permissions
COPY --chown=appuser:appuser ./ATTRIBUTION.md ./LICENSES.md ./
COPY --chown=appuser:appuser --from=build-env /home/builduser/app.jar ./app.jar

# Security: Set explicit file permissions
RUN chmod 444 ./ATTRIBUTION.md ./LICENSES.md && \
    chmod 544 ./app.jar

EXPOSE 8080

# Security: Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# Security: Use exec form to prevent shell injection
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

# Security: Add metadata labels
LABEL maintainer="security-team@company.com" \
      version="1.0.0" \
      description="Security-hardened Java service" \
      security.scan="enabled" \
      security.non-root="true" \
      security.health-check="enabled"
```

## Go Service Template

```dockerfile
# Security-Hardened Go Service Dockerfile Template
# Build Stage
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.3.20240117.0@sha256:ACTUAL_SHA256_HASH AS build-env

# Security: Install minimal build dependencies
RUN dnf --setopt=install_weak_deps=False install -q -y \
    golang \
    && \
    dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/*

# Security: Create non-root build user
RUN groupadd -r builduser && useradd -r -g builduser builduser
RUN mkdir -p /go/src /go/bin /appsrc && \
    chown -R builduser:builduser /go /appsrc

USER builduser
WORKDIR /appsrc

# Security: Configure secure Go environment
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64

# Security: Copy and verify dependencies
COPY --chown=builduser:builduser go.mod go.sum ./
RUN go mod download && go mod verify

# Security: Build with security flags
COPY --chown=builduser:builduser . .
RUN go build -ldflags="-w -s -extldflags=-static" -a -installsuffix cgo -o main main.go && \
    chmod 755 main

# Runtime Stage
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.3.20240117.0@sha256:ACTUAL_SHA256_HASH

# Security: Install minimal runtime dependencies
RUN dnf --setopt=install_weak_deps=False install -q -y \
    shadow-utils \
    ca-certificates \
    && \
    dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/* /var/log/dnf*

# Security: Create non-root user
ENV APPUSER=appuser
ENV APPUID=1000
ENV APPGID=1000

RUN groupadd -r -g "$APPGID" "$APPUSER" && \
    useradd -r -g "$APPUSER" -u "$APPUID" \
    --home "/app" \
    --create-home \
    --shell /sbin/nologin \
    "$APPUSER"

ENV GIN_MODE=release
ENV PORT=8080

WORKDIR /app
USER appuser

# Security: Copy binary with proper permissions
COPY --chown=appuser:appuser --from=build-env /appsrc/main /app/service
COPY --chown=appuser:appuser ./ATTRIBUTION.md ./LICENSES.md ./

RUN chmod 555 /app/service && \
    chmod 444 ./ATTRIBUTION.md ./LICENSES.md

EXPOSE 8080

# Security: Add health check (requires implementation in Go code)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /app/service --health-check || exit 1

ENTRYPOINT ["/app/service"]

LABEL maintainer="security-team@company.com" \
      version="1.0.0" \
      description="Security-hardened Go service" \
      security.scan="enabled" \
      security.non-root="true" \
      security.health-check="enabled" \
      security.static-binary="true"
```

## Node.js Service Template

```dockerfile
# Security-Hardened Node.js Service Dockerfile Template
# Build Stage
FROM node:20.11.0-alpine@sha256:ACTUAL_SHA256_HASH AS build

# Security: Update packages and install minimal dependencies
RUN apk update && apk upgrade && \
    apk add --no-cache dumb-init && \
    rm -rf /var/cache/apk/*

# Security: Create non-root build user
RUN addgroup -g 1001 -S builduser && \
    adduser -S -D -H -u 1001 -s /sbin/nologin builduser -G builduser

WORKDIR /usr/src/app

# Security: Copy package files with proper ownership
COPY --chown=builduser:builduser package*.json yarn.lock ./

USER builduser

# Security: Install dependencies with frozen lockfile
RUN yarn install --frozen-lockfile --production=false && \
    yarn cache clean

# Security: Copy source and build
COPY --chown=builduser:builduser . .
RUN yarn build && \
    yarn install --frozen-lockfile --production=true && \
    yarn cache clean

# Runtime Stage
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.3.20240117.0@sha256:ACTUAL_SHA256_HASH

# Security: Install minimal runtime dependencies
RUN dnf --setopt=install_weak_deps=False install -q -y \
    nodejs20 \
    shadow-utils \
    curl \
    && \
    dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/* /var/log/dnf*

RUN alternatives --install /usr/bin/node node /usr/bin/node-20 90

# Security: Create non-root user
ENV APPUSER=appuser
ENV APPUID=1000
ENV APPGID=1000

RUN groupadd -r -g "$APPGID" "$APPUSER" && \
    useradd -r -g "$APPUSER" -u "$APPUID" \
    --home "/app" \
    --create-home \
    --shell /sbin/nologin \
    "$APPUSER"

# Security: Set secure Node.js environment
ENV NODE_ENV=production
ENV PORT=8080
ENV NODE_OPTIONS="--max-old-space-size=512"

WORKDIR /app
USER appuser

# Security: Copy application with proper permissions
COPY --chown=appuser:appuser --from=build /usr/src/app/node_modules ./node_modules
COPY --chown=appuser:appuser --from=build /usr/src/app/dist ./dist
COPY --chown=appuser:appuser --from=build /usr/src/app/package.json ./package.json

# Security: Set explicit file permissions
RUN find ./node_modules -type f -exec chmod 644 {} \; && \
    find ./node_modules -type d -exec chmod 755 {} \; && \
    find ./dist -type f -exec chmod 644 {} \; && \
    find ./dist -type d -exec chmod 755 {} \; && \
    chmod 644 ./package.json

EXPOSE 8080

# Security: Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["node", "dist/main.js"]

LABEL maintainer="security-team@company.com" \
      version="1.0.0" \
      description="Security-hardened Node.js service" \
      security.scan="enabled" \
      security.non-root="true" \
      security.health-check="enabled"
```

## Security Checklist

### Pre-Build Security Checks
- [ ] Base image pinned with SHA256 hash
- [ ] Minimal base image selected
- [ ] Build dependencies minimized
- [ ] Multi-stage build implemented
- [ ] Non-root build user created

### Build Security Checks
- [ ] Dependencies verified and locked
- [ ] Build artifacts properly secured
- [ ] Temporary files cleaned up
- [ ] Build caches cleared
- [ ] Security scanning integrated

### Runtime Security Checks
- [ ] Non-root user implemented
- [ ] File permissions explicitly set
- [ ] Health check implemented
- [ ] Exec form ENTRYPOINT used
- [ ] Security labels added
- [ ] Minimal runtime dependencies
- [ ] Environment variables secured

### Post-Build Security Validation
- [ ] Container runs as non-root
- [ ] Health check functional
- [ ] Vulnerability scan passed
- [ ] Image size optimized
- [ ] Security labels present

## Common Security Anti-Patterns to Avoid

### ❌ Dangerous Practices
```dockerfile
# DON'T: Use latest tags
FROM ubuntu:latest

# DON'T: Run as root
USER root

# DON'T: Use shell form with variables
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]

# DON'T: Install unnecessary packages
RUN apt-get install -y git vim curl wget

# DON'T: Leave secrets in environment
ENV DATABASE_PASSWORD=secret123

# DON'T: Use ADD for local files
ADD app.jar /app/

# DON'T: Ignore file permissions
COPY app.jar /app/
```

### ✅ Secure Practices
```dockerfile
# DO: Pin images with SHA256
FROM ubuntu:20.04@sha256:actual_hash

# DO: Use non-root user
USER appuser

# DO: Use exec form
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

# DO: Install only necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-11-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# DO: Use build args for secrets
ARG BUILD_SECRET
RUN --mount=type=secret,id=build-secret command

# DO: Use COPY for local files
COPY --chown=appuser:appuser app.jar /app/

# DO: Set explicit permissions
RUN chmod 544 /app/app.jar
```

## Integration with CI/CD

### Security Pipeline Integration
```yaml
# Example GitHub Actions workflow
name: Security Build
on: [push, pull_request]

jobs:
  security-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build secure image
        run: docker build -f Dockerfile.secure -t app:secure .
      
      - name: Run security scan
        run: trivy image --security-checks vuln app:secure
      
      - name: Test non-root user
        run: |
          user=$(docker run --rm app:secure whoami)
          if [ "$user" = "root" ]; then
            echo "ERROR: Container running as root"
            exit 1
          fi
      
      - name: Test health check
        run: |
          docker run -d --name test-app app:secure
          sleep 30
          health=$(docker inspect test-app --format='{{.State.Health.Status}}')
          if [ "$health" != "healthy" ]; then
            echo "ERROR: Health check failed"
            exit 1
          fi
```

This template provides a comprehensive foundation for creating secure Docker images across different technology stacks while maintaining consistency and following security best practices.