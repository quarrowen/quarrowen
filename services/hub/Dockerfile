# Quarrowen hub: docker build -t quarrowen-hub services/hub
FROM rust:1-slim AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked

FROM debian:bookworm-slim
RUN useradd --system --home /data hub && mkdir -p /data && chown hub /data
COPY --from=build /src/target/release/quarrowen-hub /usr/local/bin/quarrowen-hub
USER hub
ENV HUB_BIND=0.0.0.0:24600 HUB_DATA=/data
VOLUME /data
EXPOSE 24600/tcp
CMD ["quarrowen-hub"]
