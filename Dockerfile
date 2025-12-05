# Multi-stage Dockerfile for Flutter Web IPTV Application
# Stage 1: Build Flutter Web Application
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Copy pubspec files
COPY pubspec.yaml pubspec.lock ./

# Get dependencies
RUN flutter pub get

# Copy entire project
COPY . .

# Build Flutter Web with CanvasKit renderer for 60fps performance
RUN flutter build web --release --web-renderer canvaskit

# Stage 2: Serve with dhttpd (Dart HTTP Server)
FROM dart:stable AS runtime

# Install dhttpd globally
RUN dart pub global activate dhttpd

# Create app directory
WORKDIR /app

# Copy built web files from builder stage
COPY --from=builder /app/build/web /app/web

# Create data directory for Hive persistence
RUN mkdir -p /app/data

# Expose port (internal only, not mapped to host)
EXPOSE 8080

# Set environment variable for Hive storage
ENV HIVE_STORAGE_PATH=/app/data

# Run dhttpd server
CMD ["dart", "pub", "global", "run", "dhttpd", "--host", "0.0.0.0", "--port", "8080", "--path", "/app/web"]
