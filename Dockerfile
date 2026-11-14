FROM debian:bookworm-slim

ARG TARGETARCH
ARG BEEPER_CLI_VERSION=0.6.4
ARG BEEPER_CLI_SHA256_AMD64=7ad669ff7d8fd2032e8c324edc279ecb18282f628e11a06beab17b7a74bade8a
ARG BEEPER_CLI_SHA256_ARM64=c43cefd060dae62eec131ca764fefb6e467339c81ab527599b96d32364e03339
# Beeper Server, from https://api.beeper.com/desktop/update-feed.json?bundleID=com.automattic.beeper.server&platform=linux&channel=stable&arch=<x64|arm64>
ARG BEEPER_SERVER_VERSION=4.3.308
ARG BEEPER_SERVER_SHA512_AMD64=186c3b23bb0fbe18d03462cbb7753e9510e0fbd8e4f9e383608cceeaaeb94dc4db88c31e7d54ff5740889aea8e0c2442d26f1f454f448261733e8d98005e1846
ARG BEEPER_SERVER_SHA512_ARM64=f3539fa29726458abde1478c44c12a04c36d08163599afedf23f0fc92e79db2a7230a47a15c74516d6aad9e3cd02b345a8ce3ff87f34384956cef4e57a32bf40

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      socat \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) BEEPER_ARCH=x64; EXPECTED_SHA256="${BEEPER_CLI_SHA256_AMD64}" ;; \
      arm64) BEEPER_ARCH=arm64; EXPECTED_SHA256="${BEEPER_CLI_SHA256_ARM64}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    URL="https://github.com/beeper/cli/releases/download/v${BEEPER_CLI_VERSION}/beeper-cli-${BEEPER_CLI_VERSION}-linux-${BEEPER_ARCH}.tar.gz"; \
    curl -fsSL -o /tmp/beeper-cli.tar.gz "${URL}"; \
    echo "${EXPECTED_SHA256}  /tmp/beeper-cli.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/beeper-cli; \
    tar -xzf /tmp/beeper-cli.tar.gz -C /tmp/beeper-cli --no-same-owner; \
    install -m 0755 /tmp/beeper-cli/bin/beeper /usr/local/bin/beeper; \
    rm -rf /tmp/beeper-cli /tmp/beeper-cli.tar.gz

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) SERVER_ARCH=x64; EXPECTED_SHA512="${BEEPER_SERVER_SHA512_AMD64}" ;; \
      arm64) SERVER_ARCH=arm64; EXPECTED_SHA512="${BEEPER_SERVER_SHA512_ARM64}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    URL="https://beeper-desktop.download.beeper.com/builds/beeper-server-${BEEPER_SERVER_VERSION}-linux-${SERVER_ARCH}.tar.gz"; \
    curl -fsSL -o /tmp/beeper-server.tar.gz "${URL}"; \
    echo "${EXPECTED_SHA512}  /tmp/beeper-server.tar.gz" | sha512sum -c -; \
    mkdir -p /tmp/beeper-server; \
    tar -xzf /tmp/beeper-server.tar.gz -C /tmp/beeper-server --strip-components=1 --no-same-owner; \
    install -m 0755 /tmp/beeper-server/beeper-server /usr/local/bin/beeper-server; \
    rm -rf /tmp/beeper-server /tmp/beeper-server.tar.gz

ENV HOME=/data \
    BEEPER_CLI_CONFIG_DIR=/data \
    BEEPER_CLI_BINARY_CACHE_DIR=/opt/beeper-cli-cache \
    BEEPER_SERVER_BIN=/usr/local/bin/beeper-server \
    BEEPER_SERVER_VERSION=${BEEPER_SERVER_VERSION} \
    BEEPER_PORT=23373 \
    BEEPER_INTERNAL_PORT=23374 \
    BEEPER_SERVER_ENV=production \
    BEEPER_LOG_STREAMS="beeper-server desktop-api"

LABEL org.opencontainers.image.source="https://github.com/dvcrn/beeper-headless" \
      com.beeper.cli.version="${BEEPER_CLI_VERSION}" \
      com.beeper.server.version="${BEEPER_SERVER_VERSION}"

# Pre-extract the Bun payload cache into the image so runtime invocations are instant and readable by non-root UIDs.
RUN mkdir -p "${BEEPER_CLI_BINARY_CACHE_DIR}" /data \
 && beeper --version \
 && chmod -R a+rX "${BEEPER_CLI_BINARY_CACHE_DIR}" \
 && chmod 1777 /data

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

VOLUME ["/data"]
WORKDIR /data
EXPOSE 23373

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${BEEPER_PORT}/v1/info" >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
