# VoxelCraft hub: docker build -t voxelcraft-hub services/hub
FROM rust:1-slim AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked

FROM debian:bookworm-slim
RUN useradd --system --home /data hub && mkdir -p /data && chown hub /data
COPY --from=build /src/target/release/voxelcraft-hub /usr/local/bin/voxelcraft-hub
USER hub
ENV HUB_BIND=0.0.0.0:24600 HUB_DATA=/data
VOLUME /data
EXPOSE 24600/tcp
CMD ["voxelcraft-hub"]
