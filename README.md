# beeper-headless-container

Minimal Docker container packaging the official [Beeper CLI (`beeper/cli`)](https://github.com/beeper/cli) so it directly installs and runs the headless Beeper Server in a container.

## How it works

1. The image packages the pinned `beeper` CLI binary from `github.com/beeper/cli` releases (verified by SHA-256).
2. On startup (`serve`, the default command), the entrypoint uses `beeper` itself to:
   - Install `beeper-server` into `/data` via `beeper install server` if not already present.
   - Register a managed `server` target via `beeper targets add server` if not already present.
   - Start the headless server via `beeper targets start server`.
   - Forward `0.0.0.0:23373` to `127.0.0.1:23374` with `socat` so the Beeper Desktop API / MCP endpoint is reachable from outside the container (`beeper targets start` binds `127.0.0.1`).

All state (auth, target config, `beeper-server` install, databases, and logs) is persisted in `/data`.

## Quick start

```sh
docker compose up -d
```

Or directly with `docker run`:

```sh
docker run -d \
  --name beeper-headless \
  -p 127.0.0.1:23373:23373 \
  -v ./data:/data \
  ghcr.io/dvcrn/beeper-headless:latest
```

### First-time login and verification

Sign in with your Beeper email address inside the running container:

```sh
docker exec -it beeper-headless beeper setup -t server --email you@example.com
```

Or non-interactively (no TTY):

```sh
docker exec beeper-headless beeper auth email start --email you@example.com -t server --json
docker exec beeper-headless beeper auth email response --setup-request-id <id> --code <code> -t server --json
docker exec beeper-headless beeper verify recovery-key -t server --key "ABCD-EFGH-IJKL-MNOP" --json
```

Check status or run any `beeper` command:

```sh
docker exec beeper-headless beeper status
docker exec beeper-headless beeper chats list
```

One-off CLI invocation:

```sh
docker run --rm ghcr.io/dvcrn/beeper-headless:latest --version
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `BEEPER_CLI_CONFIG_DIR` | `/data` | Directory holding CLI config, targets, server binary, and databases |
| `BEEPER_PORT` | `23373` | Container port exposed on `0.0.0.0` when `BEEPER_EXPOSE=true` |
| `BEEPER_INTERNAL_PORT` | `23374` | Loopback port passed to `beeper targets add server --port` on initial target creation |
| `BEEPER_CHANNEL` | `stable` | Beeper Server release channel (`stable` or `nightly`) |
| `BEEPER_SERVER_ENV` | `production` | Beeper Server environment (`production` or `staging`) |
| `BEEPER_AUTO_UPDATE_SERVER` | `false` | Set to `true` to run `beeper update --server` on container startup |
| `BEEPER_LOG_STREAMS` | `beeper-server desktop-api` | Space-separated `RollingLogger` log streams under `<dataDir>/logs/` to relay to container stdout (`none` to disable; other streams include `sdk` and `sqlite_worker-1..6`) |

## Auto-updates

- `.github/workflows/auto-update.yml` runs every 6 hours (and on `workflow_dispatch`), queries `gh release view --repo beeper/cli`, verifies the Linux `amd64` and `arm64` checksums from `binaries.json`, updates `VERSION` and `Dockerfile`, commits and tags `v<version>`, and triggers `.github/workflows/docker-publish.yml` to build and push multi-arch images (`latest` and `<version>`) to GHCR.
- The image tag tracks the **CLI** version. Beeper Server itself is installed from the live channel on first start and only updated when `BEEPER_AUTO_UPDATE_SERVER=true`.
- Repository setting required: **Settings → Actions → General → Workflow permissions → Read and write permissions** (so `GITHUB_TOKEN` can push commits/tags and publish to GHCR).
