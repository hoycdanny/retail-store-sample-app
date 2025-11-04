# Build Stage
# Pin to specific digest for supply chain security
FROM public.ecr.aws/amazonlinux/amazonlinux:2023@sha256:5b721d9913f7a4142ebfeb58d5a396edcae0ec8b3c85a1e1460a8a6c99d5c2e8 AS build-env

# Security labels following OCI standards
LABEL org.opencontainers.image.title="Retail Store Catalog Service - Build Stage"
LABEL org.opencontainers.image.description="Build stage for Go-based catalog microservice"
LABEL org.opencontainers.image.vendor="AWS"
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.licenses="MIT-0"
LABEL security.scan.enabled="true"

# We tell DNF not to install Recommends and Suggests packages, which are
# weak dependencies in DNF terminology, thus keeping our installed set of
# packages as minimal as possible.
# Removed git as it's not needed for module download
RUN dnf --setopt=install_weak_deps=False install -q -y \
    golang \
    ca-certificates \
    && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Create non-root build user for security
RUN useradd --system --create-home --shell /bin/false --uid 10001 builduser

# Create build directories with proper permissions
RUN mkdir -p /appsrc && \
    chown builduser:builduser /appsrc

WORKDIR /appsrc
USER builduser

# Use direct mode for Go modules to avoid external proxy dependency
ENV GOPROXY=direct
ENV GOSUMDB=off
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64

# Copy dependency files first for better layer caching
COPY --chown=builduser:builduser go.mod go.sum ./
RUN go mod download && go mod verify

# Copy source code
COPY --chown=builduser:builduser . .

# Build with security flags
RUN go build \
    -ldflags="-w -s -extldflags '-static'" \
    -a -installsuffix cgo \
    -o main main.go

# Final stage - Use minimal Alpine for health check support while maintaining security
FROM alpine:3.19@sha256:c5b1261d6d3e43071626931fc004f70149baeba2c8ec672bd4f27761f8e1ad6b

# Security labels for final image
LABEL org.opencontainers.image.title="Retail Store Catalog Service"
LABEL org.opencontainers.image.description="Production catalog microservice for retail store application"
LABEL org.opencontainers.image.vendor="AWS"
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.licenses="MIT-0"
LABEL org.opencontainers.image.source="https://github.com/aws-containers/retail-store-sample-app"
LABEL security.scan.enabled="true"
LABEL security.non-root="true"
LABEL security.readonly-rootfs="true"

# Install minimal packages for health checks and CA certificates
RUN apk add --no-cache \
    ca-certificates \
    curl \
    && \
    rm -rf /var/cache/apk/*

# Create non-root user with high UID for security
RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup -h /app -s /bin/false

WORKDIR /app
USER 10001:10001

# Copy binary with proper ownership
COPY --from=build-env --chown=10001:10001 /appsrc/main /app/main

# Copy attribution files
COPY --chown=10001:10001 ./ATTRIBUTION.md ./LICENSES.md ./

# Set production environment
ENV GIN_MODE=release
ENV PORT=8080

# Expose port for documentation (not required but good practice)
EXPOSE 8080

# Add comprehensive health check using curl
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Use exec form for better signal handling
ENTRYPOINT ["/app/main"]
