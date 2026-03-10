# Stage 1: Build Environment (Combined for stability and resource management)
FROM ghcr.io/cirruslabs/flutter:stable AS builder

USER root
WORKDIR /app

# Optimize DART VM Memory for build
ENV DART_VM_OPTIONS="--old_gen_heap_size=16384"
ENV FLUTTER_NO_ANALYTICS=1
ENV PUB_SUMMARY_ONLY=1

# 1. Pre-download artifacts (Crucial for Docker stability)
RUN flutter config --enable-web && flutter precache --web

# 2. Copy dependency files first for better caching
# Root (Flutter Web)
COPY pubspec.yaml ./
# Server (Dart shelf)
COPY bin/pubspec.yaml ./bin/

# 3. Get dependencies sequentially to avoid network/CPU contention
RUN flutter pub get && cd bin && dart pub get

# 4. Copy source code
COPY . .

# 5. Generate code (build_runner)
RUN dart run build_runner build --delete-conflicting-outputs

# 6. Build web application (VERBOSE to see progress/blocks)
RUN flutter build web --release --base-href="/" --no-tree-shake-icons --verbose

# 7. Compile server to native executable
WORKDIR /app/bin
RUN dart compile exe server.dart -o server

# ============================================
# Stage 2: Production Runtime (with NVENC support)
# ============================================
FROM debian:stable-slim

# Install runtime dependencies, tools for fetching FFmpeg, and gosu for privilege dropping
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    sqlite3 \
    libsqlite3-dev \
    curl \
    wget \
    xz-utils \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Install FFmpeg with NVIDIA NVENC support from BtbN static builds
# Falls back gracefully to CPU if GPU not available
RUN wget -q https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz \
    && tar xf ffmpeg-master-latest-linux64-gpl.tar.xz \
    && mv ffmpeg-master-latest-linux64-gpl/bin/ffmpeg /usr/local/bin/ \
    && mv ffmpeg-master-latest-linux64-gpl/bin/ffprobe /usr/local/bin/ \
    && rm -rf ffmpeg-master-latest-linux64-gpl* \
    && chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

# Create non-root user for security
RUN groupadd -r xtremuser && useradd -r -g xtremuser -G audio,video xtremuser

WORKDIR /app

# Create necessary data directories with correct permissions
RUN mkdir -p /app/data /app/web /app/recordings /tmp/xtremflow_streams \
    && chown -R xtremuser:xtremuser /app /tmp/xtremflow_streams

# Copy built artifacts from builder stage
COPY --from=builder /app/build/web /app/web
COPY --from=builder /app/bin/server /app/server

# Copy entrypoint script and set permissions
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/server /app/entrypoint.sh

# NOTE: We stay as root to allow entrypoint.sh to fix volume permissions
# The entrypoint script will drop privileges to xtremuser after fixing permissions

# Expose port
EXPOSE 8089

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8089/index.html || exit 1

# Use entrypoint to fix permissions then start server as xtremuser
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/server", "--port", "8089", "--path", "/app/web"]
