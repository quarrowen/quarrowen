# syntax=docker/dockerfile:1.7
# VoxelCraft dedicated server.
#   docker build -t voxelcraft-server .
#   docker run -p 24565:24565/udp -v voxel-data:/data -e VOXEL_MODS=skyblock voxelcraft-server
# Multi-arch: docker buildx build --platform linux/amd64,linux/arm64 -t voxelcraft-server .

ARG GODOT_VERSION=4.7.2
ARG RUST_VERSION=1.98

# --- Native extension ---------------------------------------------------------------------------
FROM rust:${RUST_VERSION}-bookworm AS native
WORKDIR /src/native
COPY native/Cargo.toml native/Cargo.lock ./
COPY native/src ./src
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/native/target \
    cargo build --release --locked \
 && mkdir -p /out && cp target/release/libvoxelcraft_native.so /out/

# --- Godot headless binary ----------------------------------------------------------------------
FROM debian:bookworm-slim AS godot
ARG GODOT_VERSION
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
RUN case "${TARGETARCH}" in \
      amd64) GODOT_ARCH=x86_64 ;; \
      arm64) GODOT_ARCH=arm64 ;; \
      *) echo "unsupported arch ${TARGETARCH}" && exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/godot.zip \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip" \
 && unzip /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH} /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot

# --- Runtime ------------------------------------------------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 voxel \
 && mkdir -p /data /mods && chown voxel:voxel /data /mods

COPY --from=godot /usr/local/bin/godot /usr/local/bin/godot
COPY --chown=voxel:voxel . /app
COPY --from=native --chown=voxel:voxel /out/libvoxelcraft_native.so /app/native/target/release/libvoxelcraft_native.so

USER voxel
WORKDIR /app
# Import once at build time: registers the GDExtension and builds Godot's resource cache.
RUN godot --headless --path /app --import 2>&1 | tail -n 5

ENV VOXEL_DATA_DIR=/data \
    VOXEL_MODS_DIR=/mods \
    VOXEL_PORT=24565 \
    VOXEL_MODS=vanilla
VOLUME ["/data"]
EXPOSE 24565/udp
STOPSIGNAL SIGTERM
ENTRYPOINT ["godot", "--headless", "--path", "/app", "res://scenes/server.tscn"]
