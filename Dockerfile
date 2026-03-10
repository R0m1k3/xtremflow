# Stage 1: Build Environment (Optimized for Docker Caching)
FROM ghcr.io/cirruslabs/flutter:stable AS builder

USER root
WORKDIR /app

# Optimize DART VM Memory
ENV DART_VM_OPTIONS="--old_gen_heap_size=16384"
ENV FLUTTER_NO_ANALYTICS=1

# 1. System Config & Precache (RARELY CHANGES)
RUN flutter config --enable-web && flutter precache --web

# 2. Dependency Resolution (ONLY UPDATES IF PUBSPEC CHANGES)
COPY pubspec.yaml ./
COPY bin/pubspec.yaml ./bin/
# Note: No .lock files found locally, so we fetch fresh ones here
RUN flutter pub get && cd bin && dart pub get

# 3. Source Code Copy (CHANGES OFTEN)
# Everything except what's in .dockerignore (built-in protection)
COPY . .

# 4. Code Generation
RUN dart run build_runner build --delete-conflicting-outputs

# 5. Compilation (SLOWEST STEP - INEVITABLE)
# This step MUST run if you modified any Dart file.
RUN flutter build web --release --base-href="/" --no-tree-shake-icons --no-pub

# 6. Native Server Compilation
RUN cd bin && dart compile exe server.dart -o server

# ============================================
# Stage 2: Production Runtime
# ============================================
FROM debian:stable-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    sqlite3 \
    libsqlite3-dev \
    curl \
    wget \
    xz-utils \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# FFmpeg with NVENC (cached unless this RUN changes)
RUN wget -q https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz \
    && tar xf ffmpeg-master-latest-linux64-gpl.tar.xz \
    && mv ffmpeg-master-latest-linux64-gpl/bin/ffmpeg /usr/local/bin/ \
    && mv ffmpeg-master-latest-linux64-gpl/bin/ffprobe /usr/local/bin/ \
    && rm -rf ffmpeg-master-latest-linux64-gpl* \
    && chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

RUN groupadd -r xtremuser && useradd -r -g xtremuser -G audio,video xtremuser
WORKDIR /app

RUN mkdir -p /app/data /app/web /app/recordings /tmp/xtremflow_streams \
    && chown -R xtremuser:xtremuser /app /tmp/xtremflow_streams

COPY --from=builder /app/build/web /app/web
COPY --from=builder /app/bin/server /app/server
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/server /app/entrypoint.sh

EXPOSE 8089

HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8089/index.html || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/server", "--port", "8089", "--path", "/app/web"]
