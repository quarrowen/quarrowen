# syntax=docker/dockerfile:1.7
# VoxelCraft dedicated server, built from an exported Godot "Linux Server" preset.
#   docker build -t voxelcraft-server .
#   docker run -p 24565:24565/udp -v voxel-data:/data -v voxel-mods:/mods -e VOXEL_MODS=skyblock voxelcraft-server
# The image holds the engine only: the mods it loads live in /mods (a volume), seeded from the copy it
# shipped with on every start (see deploy/entrypoint.sh).
# Multi-arch: docker buildx build --platform linux/amd64,linux/arm64 -t voxelcraft-server .

ARG GODOT_VERSION=4.7.2
ARG RUST_VERSION=1.98

# --- Native extension for the target architecture -----------------------------------------------
FROM rust:${RUST_VERSION}-bookworm AS native
ARG TARGETARCH
WORKDIR /src/native
COPY native/Cargo.toml native/Cargo.lock ./
COPY native/src ./src
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/native/target,id=voxelcraft-target-${TARGETARCH} \
    cargo build --release --locked \
 && mkdir -p /out && cp target/release/libvoxelcraft_native.so /out/

# --- Export (runs on the build machine's architecture) ------------------------------------------
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS export
ARG GODOT_VERSION
ARG BUILDARCH
ARG TARGETARCH
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 rsync \
 && rm -rf /var/lib/apt/lists/*
RUN case "${BUILDARCH}" in amd64) arch=x86_64 ;; arm64) arch=arm64 ;; *) echo "unsupported build arch ${BUILDARCH}"; exit 1 ;; esac \
 && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${arch}.zip" \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.${arch} /usr/local/bin/godot \
 && rm -rf /tmp/godot /tmp/godot.zip
# Only the two Linux release templates are needed out of the 1.3 GB bundle; cache them across builds.
RUN --mount=type=cache,target=/cache \
    templates="/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
 && mkdir -p "$templates" \
 && if [ ! -f "/cache/${GODOT_VERSION}/linux_release.arm64" ]; then \
      curl -fsSL -o /tmp/templates.tpz "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
      && mkdir -p "/cache/${GODOT_VERSION}" \
      && unzip -j -o /tmp/templates.tpz templates/linux_release.x86_64 templates/linux_release.arm64 templates/version.txt -d "/cache/${GODOT_VERSION}" \
      && rm /tmp/templates.tpz; \
    fi \
 && cp "/cache/${GODOT_VERSION}/"* "$templates/"
WORKDIR /project
COPY . .
COPY --from=native /out/libvoxelcraft_native.so /tmp/libvoxelcraft_native.so
RUN case "${TARGETARCH}" in \
      amd64) preset="Linux Server x86_64"; platform=linux-x86_64; build=build/server-x86_64; suffix=x86_64 ;; \
      arm64) preset="Linux Server arm64"; platform=linux-arm64; build=build/server-arm64; suffix=arm64 ;; \
      *) echo "unsupported target arch ${TARGETARCH}"; exit 1 ;; \
    esac \
 && mkdir -p "native/bin/${platform}" && cp /tmp/libvoxelcraft_native.so "native/bin/${platform}/" \
 && GODOT=/usr/local/bin/godot tools/export.sh "$preset" \
 && mkdir -p /out && cp -r "$build"/. /out/ \
 && mv "/out/voxelcraft_server.${suffix}" /out/voxelcraft_server
RUN test -x /out/voxelcraft_server && test -f /out/voxelcraft_server.pck && test -f /out/libvoxelcraft_native.so && test -d /out/mods/base

# --- Runtime ------------------------------------------------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 voxel \
 && mkdir -p /data /mods && chown voxel:voxel /data /mods
COPY --from=export --chown=voxel:voxel /out /opt/voxelcraft
COPY --chown=voxel:voxel deploy/entrypoint.sh /opt/voxelcraft/entrypoint.sh
# The engine keeps no mods beside the binary: they are seeded into /mods (the volume) and loaded from there.
RUN mv /opt/voxelcraft/mods /opt/voxelcraft/mods-seed && chmod +x /opt/voxelcraft/entrypoint.sh
USER voxel
WORKDIR /opt/voxelcraft
ENV VOXEL_DATA_DIR=/data \
    VOXEL_MODS_DIR=/mods \
    VOXEL_SEED_MODS=update \
    VOXEL_PORT=24565 \
    VOXEL_MODS=vanilla
VOLUME ["/data", "/mods"]
EXPOSE 24565/udp 24566/udp
STOPSIGNAL SIGTERM
ENTRYPOINT ["/opt/voxelcraft/entrypoint.sh"]
