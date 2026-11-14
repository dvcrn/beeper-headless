# beeper-headless-container

Docker image that packages the official [Beeper CLI (`beeper/cli`)](https://github.com/beeper/cli) together with a pinned Beeper Server binary, and uses the CLI to run the headless server.

## How it works

1. The image contains two pinned, checksum-verified binaries: the `beeper` CLI (from `github.com/beeper/cli` releases) and `beeper-server` (from Beeper's update feed), installed at `/usr/local/bin/beeper-server`.
2. On startup (`serve`, the default command), the entrypoint uses `beeper` to:
   - Register a managed `server` target via `beeper targets add server` if not already present.
   - Start the headless server via `beeper targets start server`. The CLI runs the baked-in binary through `BEEPER_SERVER_BIN`.
   - Forward `0.0.0.0:23373` to `127.0.0.1:23374` with `socat` so the Beeper Desktop API / MCP endpoint is reachable from outside the container (`beeper targets start` binds `127.0.0.1`).

All state (auth, target config, databases, and logs) is persisted in `/data`. The server's data directory is `/data/profiles/server/server`.

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
| `BEEPER_CLI_CONFIG_DIR` | `/data` | Directory holding CLI config, targets, and server data |
| `BEEPER_PORT` | `23373` | Port the API is exposed on (`0.0.0.0`) |
| `BEEPER_INTERNAL_PORT` | `23374` | Loopback port passed to `beeper targets add server --port` on initial target creation |
| `BEEPER_SERVER_ENV` | `production` | Beeper Server environment (`production` or `staging`), used on initial target creation |
| `BEEPER_LOG_STREAMS` | `beeper-server desktop-api` | Space-separated `RollingLogger` log streams under `<dataDir>/logs/` to relay to container stdout (`none` to disable; other streams include `sdk` and `sqlite_worker-1..6`) |
| `BEEPER_LOG_LEVEL` | `info` | Lowest level relayed to stdout: `trace`, `debug`, `info`, `warn` or `error`. `info` also includes the server's untyped `[log]` lines. Log files on disk are unaffected. |

## Auto-updates

- `.github/workflows/auto-update.yml` runs every 6 hours (and on `workflow_dispatch`). It checks the latest `beeper/cli` release and Beeper's stable server update feed. If either changed, it updates the versions and checksums in `Dockerfile`, writes `VERSION`, commits, tags `v<version>`, and calls `.github/workflows/docker-publish.yml` to build and push the multi-arch image.
- Image tags:
  - `:latest`
  - `:<server>` (e.g. `:4.3.308`)
  - `:<server>-cli<cli>` (e.g. `:4.3.308-cli0.6.4`), the exact pair

  Both versions are also recorded in the image labels `com.beeper.server.version` and `com.beeper.cli.version`.
- Server updates come from pulling a new image. `beeper update --server` inside the container isn't used.
