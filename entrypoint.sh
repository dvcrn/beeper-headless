#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 0 ] && [ "$1" != "serve" ]; then
  case "$1" in
    beeper|sh|bash) exec "$@" ;;
    *) exec beeper "$@" ;;
  esac
fi

CONFIG_DIR="${BEEPER_CLI_CONFIG_DIR:-/data}"
TARGET_NAME=server
PORT="${BEEPER_PORT:-23373}"
INTERNAL_PORT="${BEEPER_INTERNAL_PORT:-23374}"
CHANNEL="${BEEPER_CHANNEL:-stable}"
SERVER_ENV="${BEEPER_SERVER_ENV:-production}"
LOG_STREAMS="${BEEPER_LOG_STREAMS-beeper-server desktop-api}"

mkdir -p "${CONFIG_DIR}"

if [ ! -x "${CONFIG_DIR}/bin/beeper-server" ]; then
  echo "Installing Beeper Server via beeper CLI (channel=${CHANNEL}, env=${SERVER_ENV})..."
  beeper install server --channel "${CHANNEL}" --server-env "${SERVER_ENV}"
elif [ "${BEEPER_AUTO_UPDATE_SERVER:-false}" = "true" ]; then
  echo "Checking for Beeper Server updates via beeper CLI..."
  beeper update --server || true
fi

TARGET_FILE="${CONFIG_DIR}/targets/${TARGET_NAME}.json"
if [ ! -f "${TARGET_FILE}" ]; then
  echo "Adding managed server target on internal port ${INTERNAL_PORT}..."
  beeper targets add server "${TARGET_NAME}" --port "${INTERNAL_PORT}" --server-env "${SERVER_ENV}" --default
fi

# The CLI pretty-prints these files, one key per line, so the first match is the top-level key.
json_value() { sed -n "s/^  \"$1\": *\"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\}\$/\1/p" "$2" | head -n 1; }

ACTUAL_INTERNAL_PORT="$(json_value port "${TARGET_FILE}")"
ACTUAL_INTERNAL_PORT="${ACTUAL_INTERNAL_PORT:-${INTERNAL_PORT}}"
DATA_DIR="$(json_value dataDir "${TARGET_FILE}")"
DATA_DIR="${DATA_DIR:-${CONFIG_DIR}/profiles/server/${TARGET_NAME}}"
RUN_FILE="${CONFIG_DIR}/run/profiles/${TARGET_NAME}.json"

SOCAT_PID=""
TAIL_PID=""

stop_children() {
  for pid in "${SOCAT_PID}" "${TAIL_PID}"; do
    [ -n "${pid}" ] && kill "${pid}" 2>/dev/null || true
  done
}

cleanup() {
  trap - SIGTERM SIGINT SIGHUP
  echo "Shutting down Beeper Server..."
  [ -n "${SOCAT_PID}" ] && kill "${SOCAT_PID}" 2>/dev/null || true
  beeper targets stop "${TARGET_NAME}" || true
  stop_children
  exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

echo "Starting Beeper Server..."
beeper targets start "${TARGET_NAME}"

SERVER_PID="$(json_value pid "${RUN_FILE}")"
if [ -z "${SERVER_PID}" ] || ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  echo "Failed to determine running server PID from ${RUN_FILE}" >&2
  exit 1
fi

# `beeper targets start` always binds 127.0.0.1, so forward the public port to it.
echo "Exposing 0.0.0.0:${PORT} -> 127.0.0.1:${ACTUAL_INTERNAL_PORT}"
socat "TCP-LISTEN:${PORT},bind=0.0.0.0,fork,reuseaddr" "TCP:127.0.0.1:${ACTUAL_INTERNAL_PORT}" &
SOCAT_PID=$!

# RollingLogger writes <stream>-N.log and moves on to a new N, so follow the newest file per stream.
log_files() {
  echo "${CONFIG_DIR}/logs/profiles/${TARGET_NAME}.log"
  echo "${CONFIG_DIR}/logs/profiles/${TARGET_NAME}.err.log"
  [ "${LOG_STREAMS}" = "none" ] && return
  for stream in ${LOG_STREAMS}; do
    latest="$(ls -1t "${DATA_DIR}/logs/${stream}/${stream}-"*.log 2>/dev/null | head -n 1 || true)"
    echo "${latest:-${DATA_DIR}/logs/${stream}/${stream}-0.log}"
  done
}

CURRENT_LOGS=""
while kill -0 "${SERVER_PID}" 2>/dev/null; do
  LOGS="$(log_files)"
  if [ "${LOGS}" != "${CURRENT_LOGS}" ]; then
    [ -n "${TAIL_PID}" ] && kill "${TAIL_PID}" 2>/dev/null || true
    # Only replay history on the first tail so a rotation doesn't duplicate lines.
    mapfile -t files <<<"${LOGS}"
    tail -n "$([ -z "${CURRENT_LOGS}" ] && echo 50 || echo 0)" -F "${files[@]}" 2>/dev/null &
    TAIL_PID=$!
    CURRENT_LOGS="${LOGS}"
  fi
  sleep 5 &
  wait $! || true
done

echo "Beeper Server process (pid=${SERVER_PID}) exited; stopping container." >&2
stop_children
exit 1
