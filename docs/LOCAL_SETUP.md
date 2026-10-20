# Local setup

Run the whole Miminet stack (web app, nginx, PostgreSQL, RabbitMQ and the
Mininet emulation worker) on your machine with one command.

```bash
git clone https://github.com/mimi-net/miminet.git
cd miminet
./miminet.sh up
```

Open http://localhost and sign in as `admin@local` / `admin`.

This is for development only. Prod keeps using `start_all_containers.sh`,
`front/docker-compose-prod.yml`, `back/docker-compose.yml` and Ansible.

## Contents

- [What you need](#what-you-need)
- [Platforms](#platforms): [Linux](#linux), [Windows (WSL)](#windows-wsl),
  [Windows (Docker Desktop)](#windows-docker-desktop), [macOS](#macos)
- [What `up` does](#what-up-does)
- [Commands](#commands)
- [Configuration](#configuration)
- [Sign-in](#sign-in)
- [Day-to-day development](#day-to-day-development)
- [Troubleshooting](#troubleshooting)

## What you need

- Docker Engine 24+ with the compose plugin, or Docker Desktop.
- A Linux kernel with `openvswitch`, `sch_netem`, `sch_htb`, `sch_tbf`,
  `ip_gre`, `ipip`, `8021q` and `bridge` (built in or as modules). The
  emulation container is privileged, but it still uses the host's kernel (on
  Windows/macOS: the kernel of the VM Docker runs in). `./miminet.sh doctor`
  checks all of this.
- ~6 GB of disk space for the images; `python3` on the host for
  `./miminet.sh smoke`.

Without a suitable kernel the web UI still works: `./miminet.sh up` detects it
and starts everything except the emulation worker.

## Platforms

| Platform | Web UI | Emulation | Status |
|---|---|---|---|
| Linux (Ubuntu, Debian, Fedora, ...) | yes | yes | tested (Ubuntu 24.04), same as CI |
| Windows 10/11 + WSL 2.5+ (kernel 6.6+), Docker Engine in the distro | yes | yes | tested (WSL 3.0.3, kernel 6.18) |
| Windows + WSL older than 2.5 (kernel 5.15) | yes | **no**, no `openvswitch`/`netem` | run `wsl --update` |
| Windows + Docker Desktop (WSL 2 backend) | yes | expected yes, same WSL kernel | not tested |
| macOS (Docker Desktop, OrbStack, Colima) | yes | depends on the VM kernel | not tested, run `doctor` |

### Linux

1. Install Docker Engine: https://docs.docker.com/engine/install/ and add
   yourself to the `docker` group (`sudo usermod -aG docker $USER`, then log
   out and back in).
2. `./miminet.sh up`.

The emulation worker loads the kernel modules it needs on start (it mounts
`/lib/modules` read-only). To load them on the host now and on every boot:
`./miminet.sh doctor --fix` (uses sudo, writes
`/etc/modules-load.d/miminet.conf`).

### Windows (WSL)

The recommended setup is Docker Engine inside a WSL distro. It runs the same
commands as Linux and needs no Docker Desktop licence.

1. In PowerShell: `wsl --version`. If WSL is older than 2.5, update it, then
   restart WSL (this closes all WSL windows):
   ```powershell
   wsl --update
   wsl --shutdown
   ```
   In the distro, `uname -r` must now print 6.6 or newer. WSL 2.3 and older
   ship kernel 5.15 without `openvswitch` and `sch_netem`, so the emulation
   cannot run there; a custom kernel is not needed any more.
2. Install Docker Engine in the distro (Ubuntu shown; systemd is on by default
   in recent WSL):
   ```bash
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker $USER
   ```
   Close the terminal and open a new one so the group applies.
3. Clone the repo **into the Linux filesystem** (`~/projects/...`), not
   `/mnt/c/...`. On `/mnt/c` builds are several times slower, and file
   permissions and line endings break.
4. `./miminet.sh up`. From PowerShell, `.\miminet.ps1 up` does the same by
   forwarding to WSL.
5. Optional: `./miminet.sh doctor --fix` so the modules are loaded on every WSL
   start.

Measured on WSL 3.0.3 / 12 CPU: first `up` with base images already pulled is
about 3 min (back image ~1.5 min, front ~1 min); every later `up` takes about
25 s. Pulling `postgres`, `rabbitmq`, `nginx`, `python` and `ubuntu` from
Docker Hub adds whatever your connection needs for ~1.5 GB (15 min behind a
slow VPN).

### Windows (Docker Desktop)

Docker Desktop with the WSL 2 backend runs containers in the same WSL VM and
kernel, so the WSL version requirement above applies. Enable *Settings →
Resources → WSL integration* for your distro and run `./miminet.sh` from that
distro. If `doctor` shows modules as missing, run `./miminet.sh up` anyway: the
emulation container tries to load them itself. Not tested yet; please report
results.

### macOS

Containers run in a Linux VM whose kernel decides whether the emulation works.
`./miminet.sh doctor` asks a throwaway container about that kernel.

- **Colima / Lima** use a regular Ubuntu VM: modules are available, expected to
  work.
- **Docker Desktop / OrbStack**: depends on whether their kernel ships
  `openvswitch` and `sch_netem`. If not, use `./miminet.sh up --no-emulation`
  for UI work, or Colima for emulation.

Port 80 needs no special rights on macOS with Docker Desktop. Not tested yet;
please report results.

## What `up` does

1. Creates `.env` from `.env.example` on the first run and replaces every
   `__GENERATE__` value with a random secret.
2. Runs `scripts/doctor.sh`: docker access, kernel features, line endings,
   whether `HTTP_PORT` is free. A kernel without the needed features turns the
   emulation off with a warning instead of failing.
3. Pulls the base images that are missing.
4. Builds `miminet-front:dev` and `miminet-back:dev` (cached; rebuilds only
   what changed) and starts the services from `compose.yaml`.
5. Waits until every service passes its healthcheck (`docker compose up
   --wait`), then prints the URL and logins. If something does not get healthy
   it prints `docker compose ps` and exits non-zero.

Services (one network, addressed by name, no fixed IPs):

```
browser -> nginx :80 -> miminet (Flask/uwsgi + result worker) -> postgres
                              \-> rabbitmq <- back (Mininet/OVS worker, privileged)
```

Startup order is enforced by healthchecks: postgres, rabbitmq -> miminet ->
nginx; rabbitmq -> back. Only the web port and the RabbitMQ management UI
(`127.0.0.1:15672`) are published.

## Commands

| Command | What it does |
|---|---|
| `./miminet.sh up [--no-emulation] [--no-build] [--no-pull]` | start or update the stack and wait until healthy |
| `./miminet.sh down` | stop and remove containers; data is kept |
| `./miminet.sh reset` | `down` and delete all data volumes (asks first) |
| `./miminet.sh logs [service]` | follow logs: `miminet`, `nginx`, `postgres`, `rabbitmq`, `back` |
| `./miminet.sh ps` | container status |
| `./miminet.sh shell [service]` | shell in a container (default `miminet`), e.g. for `flask db migrate` |
| `./miminet.sh doctor [--fix]` | host checks; `--fix` loads kernel modules now and on boot |
| `./miminet.sh smoke` | end-to-end check: log in, open admin, build a network, emulate, compare packets with the reference |
| `./miminet.sh test [pytest args]` | backend test suite in a container (`scripts/back-test.sh`), e.g. `test -k arp` |

Plain `docker compose --profile emulation ...` works too once `.env` exists.

## Configuration

Everything is in `.env` (created from `.env.example`). The ones you may want to
change:

| Variable | Default | Meaning |
|---|---|---|
| `HTTP_PORT` | `80` | host port of the web UI |
| `RABBITMQ_MANAGEMENT_PORT` | `15672` | RabbitMQ UI, bound to 127.0.0.1 |
| `AUTH_PROVIDERS` | `password` | login page options: `password`, `vk`, `yandex` |
| `DEV_ADMIN_EMAIL` / `DEV_ADMIN_PASSWORD` | `admin@local` / `admin` | admin account, re-created on every start |
| `BACK_CELERY_CONCURRENCY` | `2` | parallel emulations |
| `SECRET_KEY`, `JWT_SECRET_KEY`, DB and RabbitMQ passwords | random | generated on first run; sessions survive restarts |

After editing `.env`, run `./miminet.sh up` again.

## Sign-in

With `MODE=dev` (the default here):

- the login page shows an email/password form (`AUTH_PROVIDERS=password`);
- `DEV_ADMIN_EMAIL` / `DEV_ADMIN_PASSWORD` is created or updated on every start
  with the admin role (access to `/admin/`);
- the test user `selenium` / `password` (no admin rights) used by the UI tests
  is created as before.

Safety: the app refuses to start when `MODE` is not `dev` and
`AUTH_PROVIDERS` contains `password` or `DEV_ADMIN_PASSWORD` is set.

VK and Yandex sign-in need `front/src/vk_auth.json` / `client_yandex.json` and
an OAuth app whose redirect URI points at your host, so they do not work on
`localhost` out of the box. To show their buttons anyway:
`AUTH_PROVIDERS=password,vk,yandex`.

## Day-to-day development

- The app code is baked into the image. After changing `front/src` or
  `back/src`, run `./miminet.sh up`: it rebuilds only the last layers and
  restarts what changed (about 25 s).
- Database schema changes: `./miminet.sh shell`, then `flask db migrate` /
  `flask db upgrade` (see README).
- Start over with an empty database: `./miminet.sh reset && ./miminet.sh up`.
- Backend tests: `./miminet.sh test` (~3.5 min, 154 tests).
- UI tests (Selenium/Playwright) are described in `docs/FUNCTIONAL_TESTS.md`;
  set `TEST_TARGET_HOST=127.0.0.1` against this stack.

## Troubleshooting

**`[FAIL] docker works only via sudo`.** Your shell started before you were
added to the `docker` group. Log out and back in (WSL: close the terminal, or
`wsl --terminate <distro>` from PowerShell).

**Port 80 is busy** (IIS, Skype, another stack). Set `HTTP_PORT=8080` in `.env`
and open http://localhost:8080.

**502 Bad Gateway.** The app is still starting or crashed:
`./miminet.sh logs miminet`. nginx resolves the app per request, so a 502 goes
away once the app is up; no nginx restart is needed.

**"Emulate" spins forever.** The emulation worker is not running or cannot
reach RabbitMQ: `./miminet.sh ps`, `./miminet.sh logs back`. If `up` printed
"emulation is OFF", check `./miminet.sh doctor`.

**`kernel module ... is not loaded` in the back logs, after a WSL or host
restart.** `./miminet.sh doctor --fix`, then `./miminet.sh up`.

**`/bin/bash^M: bad interpreter` or `exec ... not found`.** The repo was checked
out with CRLF line endings (Windows `core.autocrlf=true`). `.gitattributes`
forces LF for scripts now; for an old clone, re-clone with
`git clone -c core.autocrlf=input ...`.

**Image pulls are very slow or TLS fails during the build.** Often a VPN or
proxy. With a VPN in "fake IP" / TUN mode, the host resolves every name to
198.18.x.x: pulls can crawl and HTTPS from builds can break. Pause the VPN for
the first `up`, or configure a registry mirror in `/etc/docker/daemon.json`
(`"registry-mirrors"`). Later `up` runs do not download anything.

**RabbitMQ fails with `.erlang.cookie` permissions.** Only happens with the
repo on `/mnt/c` and an old bind-mounted data dir; this stack keeps RabbitMQ
data in a named volume. Move the repo into the Linux filesystem.
