# ============================================
# Stage 1: Build Flutter Web Application
# ============================================
FROM ghcr.io/cirruslabs/flutter:stable AS web-builder

USER root

WORKDIR /app

# Safe directory configuration for git
RUN git config --global --add safe.directory /app

# Optimize DART VM Memory for build to prevent OOM
ENV DART_VM_OPTIONS="--old_gen_heap_size=4096"

# Enable web support (idempotent)
RUN flutter config --enable-web

# Copy dependency files first for better caching
ARG CACHEBUST=2025-12-13-v8
COPY pubspec.yaml ./

# Get dependencies
RUN flutter pub get

# Copy source code
COPY . .

# Re-run pub get
RUN flutter pub get

# Generate code
RUN dart run build_runner build --delete-conflicting-outputs

# Clean build environment
RUN flutter clean

# Build web application
RUN flutter build web --release --base-href="/" --no-wasm-dry-run --no-tree-shake-icons --verbose

# ============================================
# Stage 2: Compile Configurable Server (Native)
# ============================================
FROM dart:stable AS server-builder

WORKDIR /app

COPY pubspec.yaml ./
COPY bin/ ./bin/
COPY lib/ ./lib/

# Get dependencies
RUN dart pub get

# Compile server to native executable
# This drastically reduces startup time and memory footprint (vs JIT)
RUN dart compile exe bin/server.dart -o bin/server

# ============================================
# Stage 3: Production Runtime
# ============================================
FROM debian:stable-slim

# Install runtime dependencies
# - ffmpeg: For transcoding
# - ca-certificates: For HTTPS requests
# - sqlite3: For database
# - libsqlite3-0: Shared library for sqlite
# - curl: For healthchecks (optional but good practice)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    ca-certificates \
    sqlite3 \
    libsqlite3-0 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r xtremuser && useradd -r -g xtremuser -G audio,video xtremuser

WORKDIR /app

# Create necessary data directories with correct permissions
RUN mkdir -p /app/data /app/web /tmp/xtremflow_streams \
    && chown -R xtremuser:xtremuser /app /tmp/xtremflow_streams

# Copy built artifacts
COPY --from=web-builder /app/build/web /app/web
COPY --from=server-builder /app/bin/server /app/server

# Set permission for the executable
RUN chmod +x /app/server

# Switch to non-root user
USER xtremuser

# Expose port
EXPOSE 8089

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8089/index.html || exit 1

# Start server
CMD ["/app/server", "--port", "8089", "--path", "/app/web"]
