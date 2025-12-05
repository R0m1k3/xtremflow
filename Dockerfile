# ============================================
# Stage 1: Build Flutter Web Application
# ============================================
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Safe directory configuration for git
RUN git config --global --add safe.directory /app

# Enable web support (idempotent)
RUN flutter config --enable-web

# Copy dependency files first for better caching
COPY pubspec.yaml ./

# Get dependencies
RUN flutter pub get

# Copy source code
COPY . .

# Build web application (HTML renderer for compatibility)
RUN flutter build web --release --web-renderer html

# ============================================
# Stage 2: Serve with dhttpd (Dart HTTP server)
# ============================================
FROM dart:stable

WORKDIR /app

# Install dhttpd globally
RUN dart pub global activate dhttpd

# Copy built web application from builder stage
COPY --from=builder /app/build/web /app/web

# Expose port (internal only, not mapped to host)
EXPOSE 8080

# Serve web application
CMD ["/root/.pub-cache/bin/dhttpd", "--host", "0.0.0.0", "--port", "8080", "--path", "/app/web"]
