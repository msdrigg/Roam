FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef
WORKDIR /app

FROM chef AS planner
COPY backend/. .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
# apns-h2's default crypto provider (aws-lc-rs) builds aws-lc-sys from source, which
# needs cmake on top of the C toolchain already present in the rust image. (The old
# `a2` crate used ring, which did not require cmake.)
RUN apt-get update \
    && apt-get install -y --no-install-recommends cmake \
    && rm -rf /var/lib/apt/lists/*
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json
# Build application
COPY backend/. .
RUN SQLX_OFFLINE=true cargo build --release --bin roam-backend

# We do not need the Rust toolchain to run the binary!
FROM debian:stable-slim AS runtime
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar \
    && arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
        amd64) ipsw_arch="x86_64" ;; \
        arm64) ipsw_arch="arm64" ;; \
        *) echo "Unsupported architecture for ipsw: $arch" >&2; exit 1 ;; \
    esac \
    # Resolve the latest tag from the release redirect rather than api.github.com:
    # the API rate-limits unauthenticated builders (403), which silently left
    # ipsw_version empty and 404'd the download below.
    && ipsw_version="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/blacktop/ipsw/releases/latest | sed -n 's|.*/tag/v\(.*\)$|\1|p')" \
    && if [ -z "$ipsw_version" ]; then echo "Could not resolve latest ipsw version" >&2; exit 1; fi \
    && curl -fsSL "https://github.com/blacktop/ipsw/releases/latest/download/ipsw_${ipsw_version}_linux_${ipsw_arch}.tar.gz" -o /tmp/ipsw.tar.gz \
    && tar -xzf /tmp/ipsw.tar.gz -C /usr/local/bin ipsw \
    && chmod +x /usr/local/bin/ipsw \
    && rm -rf /var/lib/apt/lists/* /tmp/ipsw.tar.gz
COPY --from=builder /app/target/release/roam-backend /usr/local/bin
COPY docs/src/pages /app/docs/pages
ENV AI_RESPONDER_DOCS_DIR=/app/docs/pages
ENTRYPOINT ["/usr/local/bin/roam-backend"]
