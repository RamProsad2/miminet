#!/usr/bin/env bash
# miminet.sh — one entry point for the local dev stack (compose.yaml).
#
# Usage: ./miminet.sh <command> [options]   (./miminet.sh help for the list)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [ -t 1 ]; then B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'; else B= G= Y= R= N=; fi
info() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s[error]%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

compose() { docker compose --profile emulation "$@"; }

env_value() { grep -E "^$1=" .env 2>/dev/null | tail -1 | cut -d= -f2-; }

random_secret() {
    if command -v openssl >/dev/null 2>&1; then openssl rand -hex 24
    else head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# Create .env from .env.example on first run, filling in random secrets.
ensure_env() {
    [ -f .env ] && return
    [ -f .env.example ] || die ".env.example is missing"
    info "creating .env from .env.example (random passwords and secrets)"
    local line out=""
    while IFS= read -r line || [ -n "$line" ]; do
        while [[ "$line" == *__GENERATE__* ]]; do
            line="${line/__GENERATE__/$(random_secret)}"
        done
        out+="$line"$'\n'
    done < .env.example
    printf '%s' "$out" > .env
}

print_ready() {
    local port user pass url
    port="$(env_value HTTP_PORT)"; port="${port:-80}"
    url="http://localhost$([ "$port" = 80 ] || echo ":$port")"
    user="$(env_value DEV_ADMIN_EMAIL)"; pass="$(env_value DEV_ADMIN_PASSWORD)"
    echo
    printf '%sMiminet is up:%s %s\n' "$G" "$N" "$url"
    [ -n "$user" ] && echo "  admin login:    $user / $pass"
    echo "  test user:      selenium / password"
    echo "  RabbitMQ UI:    http://localhost:$(env_value RABBITMQ_MANAGEMENT_PORT || true) ($(env_value RABBITMQ_DEFAULT_USER) / see .env)"
    [ "${1:-}" = no-emulation ] && warn "emulation is OFF: networks can be edited, but 'Emulate' will wait forever"
    echo "  logs: ./miminet.sh logs   stop: ./miminet.sh down"
}

cmd_up() {
    local emulation=1 build_flag=(--build) pull=1
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-emulation) emulation=0 ;;
            --no-build) build_flag=(--no-build) ;;
            --no-pull) pull=0 ;;
            *) die "unknown option for up: $1" ;;
        esac
        shift
    done

    ensure_env

    info "checking the host (scripts/doctor.sh)"
    local rc=0
    bash scripts/doctor.sh || rc=$?
    case "$rc" in
        0) ;;
        2)
            if [ "$emulation" = 1 ]; then
                warn "this kernel cannot run the emulation; starting the web UI only (see above)"
                emulation=0
            fi ;;
        *) die "the host is not ready, see the [FAIL] lines above" ;;
    esac

    local services=(postgres rabbitmq miminet nginx)
    [ "$emulation" = 1 ] && services+=(back)

    # Pull only images that are missing; a failed pull (offline, registry
    # down) is not fatal when the image is already present.
    if [ "$pull" = 1 ]; then
        info "pulling missing base images"
        compose pull --quiet --ignore-pull-failures --policy missing postgres rabbitmq nginx \
            || warn "image pull failed; will use local images if present"
    fi

    info "building and starting: ${services[*]}"
    local start=$SECONDS
    if ! compose up -d --wait --wait-timeout 600 "${build_flag[@]}" "${services[@]}"; then
        echo
        compose ps -a >&2 || true
        die "some services did not become healthy. Inspect: ./miminet.sh logs <service>"
    fi
    info "stack is healthy in $((SECONDS - start))s"
    print_ready "$([ "$emulation" = 1 ] || echo no-emulation)"
}

cmd_down() { compose down "$@"; }

cmd_reset() {
    read -r -p "Delete ALL local data (database, RabbitMQ, uploads)? [y/N] " ans
    [ "$ans" = y ] || [ "$ans" = Y ] || { echo "aborted"; return 1; }
    compose down -v
}

cmd_logs() { compose logs -f --tail=200 "$@"; }

cmd_ps() { compose ps -a; }

cmd_shell() {
    local svc="${1:-miminet}"
    compose exec "$svc" bash 2>/dev/null || compose exec "$svc" sh
}

cmd_smoke() {
    local port
    port="$(env_value HTTP_PORT)"; port="${port:-80}"
    python3 scripts/smoke-emulation.py --base-url "http://localhost:$port" \
        --email "$(env_value DEV_ADMIN_EMAIL)" --password "$(env_value DEV_ADMIN_PASSWORD)" "$@"
}

cmd_help() {
    cat <<EOF
${B}miminet.sh${N} — local dev stack (compose.yaml)

  up [--no-emulation] [--no-build] [--no-pull]
                 check the host, create .env if missing, build (cached, picks
                 up code changes), start, wait until healthy.
                 --no-emulation skips the Mininet worker (web UI only).
  down           stop and remove containers (data volumes are kept)
  reset          down + delete all data volumes (asks first)
  logs [svc]     follow logs (services: miminet nginx postgres rabbitmq back)
  ps             container status
  shell [svc]    shell in a container (default: miminet)
  doctor [--fix] check kernel modules, docker, ports, line endings;
                 --fix loads the modules now and on boot (sudo)
  smoke          end-to-end check: log in, build a network, emulate, verify
  test [args]    backend test suite in a container (scripts/back-test.sh)

Settings live in .env (created from .env.example on first 'up').
EOF
}

cmd="${1:-help}"
[ $# -gt 0 ] && shift
case "$cmd" in
    up)     cmd_up "$@" ;;
    down)   cmd_down "$@" ;;
    reset)  cmd_reset ;;
    logs)   cmd_logs "$@" ;;
    ps)     cmd_ps ;;
    shell)  cmd_shell "$@" ;;
    doctor) bash scripts/doctor.sh "$@" ;;
    smoke)  cmd_smoke "$@" ;;
    test)   BACK_IMAGE="${BACK_IMAGE:-miminet-back:dev}" bash scripts/back-test.sh test "$@" ;;
    help|-h|--help) cmd_help ;;
    *) cmd_help; die "unknown command: $cmd" ;;
esac
