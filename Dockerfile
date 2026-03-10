# Stage 1: Build Environment
FROM ghcr.io/cirruslabs/flutter:stable AS builder

USER root
WORKDIR /app

# Version tag to identify the build in logs
RUN echo "XTREMFLOW_BUILD_VERSION: 2.0_STABLE_TIMEOUTS"

# Optimize DART VM Memory for build
ENV DART_VM_OPTIONS="--old_gen_heap_size=16384"
ENV FLUTTER_NO_ANALYTICS=1
ENV PUB_SUMMARY_ONLY=1

# 1. Pre-download artifacts (Force download before build starts)
RUN echo "Step 1: Flutter Config and Precache..." && \
    flutter config --enable-web && \
    flutter precache --web --verbose

# 2. Copy dependency files first for caching
COPY pubspec.yaml ./
COPY bin/pubspec.yaml ./bin/

# 3. Get dependencies (Verbose to see progress)
RUN echo "Step 3: Fetching dependencies..." && \
    flutter pub get --verbose && \
    cd bin && dart pub get --verbose

# 4. Copy source code
COPY . .

# 5. Generate code (build_runner)
RUN echo "Step 5: Code Generation..." && \
    dart run build_runner build --delete-conflicting-outputs

# 6. Build web application (VERBOSE + NO-PUB to prevent network access)
RUN echo "Step 6: Building Web Application..." && \
    flutter build web --release --base-href="/" --no-tree-shake-icons --no-pub --verbose

# 7. Compile server to native executable
RUN echo "Step 7: Compiling Backend Server..." && \
    cd bin && dart compile exe server.dart -o server

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

# FFmpeg with NVENC
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
