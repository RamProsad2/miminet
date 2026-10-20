#!/usr/bin/env bash
# doctor.sh — check whether this host can run the Miminet dev stack.
#
# The emulation container is privileged but still uses the HOST kernel, so
# every kernel feature Mininet/OVS/tc need must exist on the host (or in the
# WSL2 / Docker Desktop VM). This script reports what is missing and, with
# --fix, loads the modules now and on every boot (needs sudo).
#
# Usage: scripts/doctor.sh [--fix]
# Exit:  0 ready, 1 docker unusable (nothing runs), 2 emulation unavailable
#        (the web UI still runs: ./miminet.sh up --no-emulation)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

if [ -t 1 ]; then G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'; else G= Y= R= N=; fi
ok()   { printf '  %s[ok]%s   %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s[warn]%s %s\n' "$Y" "$N" "$*"; }
kbad() { printf '  %s[FAIL]%s %s\n' "$R" "$N" "$*"; KERNEL_FAILED=1; }
tbad() { printf '  %s[FAIL]%s %s\n' "$R" "$N" "$*"; TOOL_FAILED=1; }
KERNEL_FAILED=0
TOOL_FAILED=0

# Modules the back container loads itself (ENTRYPOINT.sh) when they exist.
MODULES="openvswitch sch_netem sch_htb sch_tbf ip_gre ipip 8021q bridge"
# kernel option -> module name
CHECKS="OPENVSWITCH:openvswitch NET_SCH_NETEM:sch_netem NET_SCH_HTB:sch_htb NET_SCH_TBF:sch_tbf NET_IPGRE:ip_gre NET_IPIP:ipip BRIDGE:bridge VXLAN:vxlan VLAN_8021Q:8021q VETH:veth TUN:tun"

OS="$(uname -s)"
IS_WSL=0
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1

echo "== Tooling"
DOCKER_OK=0
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        DOCKER_OK=1
        ok "docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    elif sudo -n docker info >/dev/null 2>&1 || id -nG 2>/dev/null | grep -qw docker; then
        tbad "docker works only via sudo in this shell. Run: sudo usermod -aG docker \$USER, then log out and back in (WSL: close the terminal or 'wsl --terminate <distro>')"
    else
        tbad "docker CLI found, but the daemon is unreachable (start it: sudo systemctl start docker, or start Docker Desktop)"
    fi
    if docker compose version >/dev/null 2>&1; then
        ok "docker compose $(docker compose version --short 2>/dev/null)"
    else
        tbad "docker compose plugin missing (install docker-compose-plugin)"
    fi
else
    case "$OS:$IS_WSL" in
        Linux:1) tbad "docker is not installed. Install Docker Engine inside the WSL distro (docs/LOCAL_SETUP.md), or enable Docker Desktop -> Settings -> Resources -> WSL integration" ;;
        Darwin:*) tbad "docker is not installed (Docker Desktop, OrbStack or Colima)" ;;
        *) tbad "docker is not installed: https://docs.docker.com/engine/install/" ;;
    esac
fi

echo "== Host"
KREL="$(uname -r)"
echo "  os: $OS, kernel: $KREL$([ "$IS_WSL" = 1 ] && echo ' (WSL2)')"

# Read kernel config and loaded modules. On Linux that is the host itself;
# elsewhere (macOS, Windows without WSL) the containers run in a VM, so ask a
# throwaway privileged container about the VM's kernel.
KCONFIG=""
LOADED=""
KSOURCE="host"
if [ "$OS" = Linux ]; then
    if [ -r /proc/config.gz ]; then KCONFIG="$(zcat /proc/config.gz)"
    elif [ -r "/boot/config-$KREL" ]; then KCONFIG="$(cat "/boot/config-$KREL")"
    fi
    LOADED="$(ls /sys/module 2>/dev/null)"
elif [ "$DOCKER_OK" = 1 ]; then
    KSOURCE="docker VM"
    out="$(docker run --rm --privileged alpine:3 sh -c 'uname -r; echo ---; zcat /proc/config.gz 2>/dev/null; echo ---; ls /sys/module' 2>/dev/null)"
    echo "  docker VM kernel: $(printf '%s\n' "$out" | head -1)"
    KCONFIG="$(printf '%s\n' "$out" | awk '/^---$/{n++; next} n==1')"
    LOADED="$(printf '%s\n' "$out" | awk '/^---$/{n++; next} n==2')"
fi

if [ "$IS_WSL" = 1 ]; then
    case "$KREL" in
        5.*) kbad "WSL kernel $KREL has no openvswitch/netem/htb/gre. In Windows PowerShell run 'wsl --update', then 'wsl --shutdown' (WSL 2.5+ ships kernel 6.6+ with them as modules)" ;;
    esac
    case "$REPO" in
        /mnt/*) warn "repo is on the Windows filesystem ($REPO): builds are slow and file permissions break. Clone it into the Linux FS (~/...)" ;;
    esac
fi

echo "== Kernel features ($KSOURCE)"
is_loaded() { printf '%s\n' "$LOADED" | grep -qx "$1"; }
for pair in $CHECKS; do
    opt="${pair%%:*}"; mod="${pair##*:}"
    if [ -z "$KCONFIG" ]; then
        warn "$mod: cannot read the kernel config; the back container will try 'modprobe $mod'"
        continue
    fi
    val=$(printf '%s\n' "$KCONFIG" | grep -E "^CONFIG_${opt}=" | cut -d= -f2)
    case "$val" in
        y) ok "$mod (built-in)" ;;
        m)
            if is_loaded "$mod"; then
                ok "$mod (module, loaded)"
            elif [ "$FIX" = 1 ] && [ "$OS" = Linux ] && sudo modprobe "$mod" 2>/dev/null; then
                ok "$mod (module, loaded now)"
            else
                ok "$mod (module, not loaded yet; the back container loads it on start)"
            fi ;;
        *) kbad "$mod: CONFIG_${opt} is not set in this kernel" ;;
    esac
done

if [ "$FIX" = 1 ] && [ "$OS" = Linux ] && [ "$KERNEL_FAILED" = 0 ] && [ -d /etc/modules-load.d ]; then
    conf=/etc/modules-load.d/miminet.conf
    want="$(printf '%s\n' $MODULES)"
    if [ "$(cat "$conf" 2>/dev/null)" != "$want" ]; then
        if printf '%s\n' "$want" | sudo tee "$conf" >/dev/null; then
            ok "modules will load on boot ($conf)"
        else
            warn "could not write $conf"
        fi
    else
        ok "modules load on boot ($conf)"
    fi
fi

echo "== Repo"
crlf="$(cd "$REPO" && git ls-files -z '*.sh' 'back/Dockerfile' 'front/Dockerfile' '*.template' 2>/dev/null \
        | xargs -0 -r grep -l $'\r' 2>/dev/null)"
if [ -n "$crlf" ]; then
    tbad "CRLF line endings (containers fail with 'bad interpreter'): $(echo $crlf). Re-clone with: git clone -c core.autocrlf=input <url>"
else
    ok "shell scripts have LF line endings"
fi

port="${HTTP_PORT:-}"
[ -z "$port" ] && port="$(grep -E '^HTTP_PORT=' "$REPO/.env" 2>/dev/null | cut -d= -f2)"
port="${port:-80}"
if command -v ss >/dev/null 2>&1 && ss -ltnH "sport = :$port" 2>/dev/null | grep -q .; then
    if [ "$DOCKER_OK" = 1 ] && docker ps --filter "publish=$port" --format '{{.Labels}}' 2>/dev/null | grep -q 'com.docker.compose.project=miminet'; then
        ok "port $port is used by this stack"
    else
        warn "port $port is busy: set HTTP_PORT=8080 (or another free port) in .env"
    fi
else
    ok "port $port is free"
fi

echo
if [ "$TOOL_FAILED" = 1 ]; then
    echo "Result: fix the [FAIL] items above first."
    exit 1
fi
if [ "$KERNEL_FAILED" = 1 ]; then
    echo "Result: emulation will NOT work on this host. The web UI still runs: ./miminet.sh up --no-emulation"
    exit 2
fi
echo "Result: ready."
