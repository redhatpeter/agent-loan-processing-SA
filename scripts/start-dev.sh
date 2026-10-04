#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly BACKEND_DIR="$ROOT_DIR/src/backend"
readonly MCP_DIR="$ROOT_DIR/src/biz_api/loan_approval"
readonly FRONTEND_DIR="$ROOT_DIR/src/frontend"
readonly BACKEND_PYTHON="$BACKEND_DIR/.venv/bin/python"
readonly MCP_PYTHON="$MCP_DIR/.venv/bin/python"
readonly BACKEND_PORT=8001
readonly MCP_PORT=8070
readonly FRONTEND_PORT=5173

INSTALL=false
RELOAD=true
SERVICE_NAMES=()
SERVICE_PIDS=()

usage() {
    cat <<'EOF'
Usage: ./scripts/start-dev.sh [options]

Start the loan-processing MCP server, backend, and frontend for local development.

Options:
  --install    Restore Python and Node.js dependencies before startup.
  --no-reload  Disable Uvicorn auto-reload for the backend.
  -h, --help   Show this help message.
EOF
}

log() {
    printf '[dev] %s\n' "$*"
}

fail() {
    printf '[dev] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' was not found."
}

require_linux_command() {
    local command_path
    command_path="$(command -v "$1" 2>/dev/null || true)"
    [[ -n "$command_path" ]] || fail "Required command '$1' was not found."
    [[ "$command_path" != /mnt/* ]] ||
        fail "'$1' resolves to a Windows executable ($command_path). Install it inside WSL."
}

port_is_in_use() {
    python3 - "$1" <<'PY'
import socket
import sys

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.settimeout(0.5)
    sys.exit(0 if sock.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)
PY
}

require_available_port() {
    local port="$1"
    local service="$2"
    if port_is_in_use "$port"; then
        fail "Port $port is already in use; cannot start $service."
    fi
}

restore_dependencies() {
    require_linux_command uv
    require_linux_command node
    require_linux_command npm

    log "Restoring backend dependencies..."
    (
        cd "$BACKEND_DIR"
        uv sync --prerelease=allow
    )

    log "Restoring MCP dependencies..."
    (
        cd "$MCP_DIR"
        uv sync
    )

    log "Restoring frontend dependencies..."
    (
        cd "$FRONTEND_DIR"
        npm ci
    )
}

preflight() {
    require_command python3
    require_command curl
    require_command setsid
    require_linux_command node
    require_linux_command npm

    [[ -f "$BACKEND_DIR/.env.dev" ]] ||
        fail "Missing $BACKEND_DIR/.env.dev."
    [[ -x "$BACKEND_PYTHON" ]] ||
        fail "Missing backend environment. Run this script with --install."
    [[ -x "$MCP_PYTHON" ]] ||
        fail "Missing MCP environment. Run this script with --install."
    [[ -d "$FRONTEND_DIR/node_modules" ]] ||
        fail "Missing frontend dependencies. Run this script with --install."

    require_available_port "$MCP_PORT" "the MCP server"
    require_available_port "$BACKEND_PORT" "the backend"
    require_available_port "$FRONTEND_PORT" "the frontend"
}

prefix_output() {
    local service="$1"
    while IFS= read -r line; do
        printf '[%s] %s\n' "$service" "$line"
    done
}

start_service() {
    local name="$1"
    local working_directory="$2"
    shift 2

    log "Starting $name..."
    (
        cd "$working_directory"
        exec setsid "$@"
    ) > >(prefix_output "$name") 2> >(prefix_output "$name" >&2) &

    SERVICE_NAMES+=("$name")
    SERVICE_PIDS+=("$!")
}

service_is_running() {
    kill -0 "$1" 2>/dev/null
}

wait_for_tcp() {
    local name="$1"
    local pid="$2"
    local port="$3"
    local timeout="$4"
    local deadline=$((SECONDS + timeout))

    until port_is_in_use "$port"; do
        service_is_running "$pid" ||
            fail "$name exited before port $port became ready."
        ((SECONDS < deadline)) ||
            fail "Timed out waiting for $name on port $port."
        sleep 1
    done

    log "$name is ready on port $port."
}

wait_for_http() {
    local name="$1"
    local pid="$2"
    local url="$3"
    local timeout="$4"
    local deadline=$((SECONDS + timeout))

    until curl --fail --silent --show-error --output /dev/null "$url" 2>/dev/null; do
        service_is_running "$pid" ||
            fail "$name exited before $url became ready."
        ((SECONDS < deadline)) ||
            fail "Timed out waiting for $name at $url."
        sleep 1
    done

    log "$name is ready at $url."
}

stop_services() {
    local exit_code=$?
    trap - EXIT INT TERM

    if ((${#SERVICE_PIDS[@]} > 0)); then
        log "Stopping development services..."
    fi

    for ((index = ${#SERVICE_PIDS[@]} - 1; index >= 0; index--)); do
        local pid="${SERVICE_PIDS[$index]}"
        if service_is_running "$pid"; then
            kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        fi
    done

    local deadline=$((SECONDS + 10))
    while ((SECONDS < deadline)); do
        local running=false
        for pid in "${SERVICE_PIDS[@]}"; do
            if service_is_running "$pid"; then
                running=true
                break
            fi
        done
        [[ "$running" == false ]] && break
        sleep 0.2
    done

    for pid in "${SERVICE_PIDS[@]}"; do
        if service_is_running "$pid"; then
            kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        fi
        wait "$pid" 2>/dev/null || true
    done

    exit "$exit_code"
}

monitor_services() {
    while true; do
        for index in "${!SERVICE_PIDS[@]}"; do
            local pid="${SERVICE_PIDS[$index]}"
            if ! service_is_running "$pid"; then
                local exit_code=0
                wait "$pid" || exit_code=$?
                fail "${SERVICE_NAMES[$index]} exited unexpectedly with status $exit_code."
            fi
        done
        sleep 1
    done
}

while (($# > 0)); do
    case "$1" in
        --install)
            INSTALL=true
            ;;
        --no-reload)
            RELOAD=false
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "Unknown option: $1"
            ;;
    esac
    shift
done

trap stop_services EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$INSTALL" == true ]]; then
    restore_dependencies
fi

preflight

start_service "mcp" "$MCP_DIR" env PROFILE=dev "$MCP_PYTHON" main.py
wait_for_tcp "MCP server" "${SERVICE_PIDS[-1]}" "$MCP_PORT" 60

backend_command=(
    env
    PROFILE=dev
    "$BACKEND_PYTHON"
    -m
    uvicorn
    app.main:app
    --host
    0.0.0.0
    --port
    "$BACKEND_PORT"
)
if [[ "$RELOAD" == true ]]; then
    backend_command+=(--reload)
fi
start_service "backend" "$BACKEND_DIR" "${backend_command[@]}"
wait_for_http \
    "Backend" \
    "${SERVICE_PIDS[-1]}" \
    "http://localhost:$BACKEND_PORT/openapi.json" \
    120

start_service \
    "frontend" \
    "$FRONTEND_DIR" \
    env \
    "VITE_API_URL=http://localhost:$BACKEND_PORT/api" \
    npm \
    run \
    dev \
    -- \
    --host \
    0.0.0.0
wait_for_http "Frontend" "${SERVICE_PIDS[-1]}" "http://localhost:$FRONTEND_PORT" 60

cat <<EOF

[dev] All services are running:
[dev]   Frontend:    http://localhost:$FRONTEND_PORT
[dev]   Backend API: http://localhost:$BACKEND_PORT
[dev]   API docs:    http://localhost:$BACKEND_PORT/docs
[dev]   MCP server:  http://localhost:$MCP_PORT/mcp
[dev]
[dev] Press Ctrl+C to stop all services.
EOF

monitor_services
