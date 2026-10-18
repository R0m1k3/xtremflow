# Stage 1: Build Environment (Optimized for Docker Caching)
# SDK Flutter officiel, version épinglée — la même que la CI. L'image
# ghcr.io/cirruslabs/flutter:stable n'est plus mise à jour : elle était
# restée sur Flutter 3.44.0 / Dart 3.12.0 (mai 2026), loin derrière la
# version stable réelle.
FROM debian:stable-slim AS builder

ARG FLUTTER_VERSION=3.47.6

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt \
    && git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

WORKDIR /app

# Optimize DART VM Memory
ENV DART_VM_OPTIONS="--old_gen_heap_size=16384"
ENV FLUTTER_NO_ANALYTICS=1

# 1. System Config & Precache (RARELY CHANGES)
RUN flutter config --enable-web && flutter precache --web

# 2. Dependency Resolution (ONLY UPDATES IF PUBSPEC CHANGES)
# Le lockfile est versionné : le build résout exactement les versions
# committées au lieu d'en chercher de nouvelles à chaque build.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# 3. Source Code Copy (CHANGES OFTEN)
# Everything except what's in .dockerignore (built-in protection)
COPY . .

# 4. Code Generation
RUN dart run build_runner build --delete-conflicting-outputs

# 5. Compilation (SLOWEST STEP - INEVITABLE)
# This step MUST run if you modified any Dart file.
RUN flutter build web --release --base-href="/" --no-tree-shake-icons --no-pub

# ============================================
# Stage 2: Serveur Rust
# ============================================
# Bookworm (glibc 2.36) : le binaire tourne tel quel sur le runtime
# debian:stable-slim, plus récent. Version épinglée comme le SDK Flutter.
FROM rust:1.98.1-slim-bookworm AS server-builder

WORKDIR /server

# Dépendances compilées dans une couche à part : elles ne sont recompilées
# que si Cargo.toml/Cargo.lock changent, pas à chaque modification du code.
COPY server/Cargo.toml server/Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs \
    && cargo build --release --locked \
    && rm -rf src target/release/xtremflow-server* target/release/deps/xtremflow_server*

COPY server/src ./src
RUN cargo build --release --locked

# ============================================
# Stage 3: Production Runtime
# ============================================
FROM debian:stable-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    sqlite3 \
    curl \
    wget \
    xz-utils \
    gosu \
    fonts-dejavu-core \
    tzdata \
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
COPY --from=server-builder /server/target/release/xtremflow-server /app/server
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/server /app/entrypoint.sh

EXPOSE 8089

HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8089/index.html || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/server", "--port", "8089", "--path", "/app/web"]
