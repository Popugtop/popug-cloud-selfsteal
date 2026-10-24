#!/usr/bin/env bash
# selfsteal — camouflage website for a Reality "self-steal" node.
#
# Installs Caddy (Docker) with a static template on the node. Caddy listens on
# a loopback port; Xray (Reality) uses that port as its `target`. The node itself
# (Remnanode / Xray) is NOT installed or modified by this script.
#
#   bash <(curl -Ls <release-url>/selfsteal.sh) @ install
#   selfsteal install|update|uninstall|status|logs|restart|template|domain|cert|templates
#
# Run `selfsteal --help` for the options.
set -Eeuo pipefail
umask 022

# ---------------------------------------------------------------------------
# Release data. Replaced by tools/build-release.mjs when a release is built:
# pinned version, repository and the SHA256 of every template archive.
# @@EMBED:BEGIN@@
VERSION="dev"
REPO=""
TEMPLATE_NAMES=""
template_desc() { case "$1" in *) echo "" ;; esac; }
template_sha256() { case "$1" in *) echo "" ;; esac; }
# @@EMBED:END@@
# ---------------------------------------------------------------------------

APP_DIR="/opt/selfsteal"
BIN_PATH="/usr/local/bin/selfsteal"
CONTAINER="selfsteal-caddy"
CADDY_IMAGE="caddy:2.11.7@sha256:504a44d7d74bd2bc28a66afc4774912fc21223ca8a67734af1c54ab2f999b489"
DEFAULT_PORT=8443
STATE_FILE="$APP_DIR/state.env"

# option defaults (flags or SELFSTEAL_* environment variables)
DOMAIN="${SELFSTEAL_DOMAIN:-}"
TEMPLATE="${SELFSTEAL_TEMPLATE:-}"
PORT="${SELFSTEAL_PORT:-}"
SEED="${SELFSTEAL_SEED:-}"
ACME_EMAIL="${SELFSTEAL_EMAIL:-}"
ACME_CA="${SELFSTEAL_ACME_CA:-}"
ACME_CA_ROOT="${SELFSTEAL_ACME_CA_ROOT:-}"
BASE_URL="${SELFSTEAL_BASE_URL:-}"
OUT_DIR="" MODE="public"
YES=0 STAGING=0 SKIP_DNS=0 NO_UFW=0 ENABLE_UFW=0 WITH_NODE=0 PURGE=0 FOLLOW=0 TAIL=100
ARGS=()
TMP=""
NEED_RESTART=0

# ---------------------------------------------------------------- output ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m' C_GRN=$'\033[32m' C_YEL=$'\033[33m' C_CYA=$'\033[36m' C_DIM=$'\033[2m' C_BLD=$'\033[1m' C_OFF=$'\033[0m'
else
  C_RED="" C_GRN="" C_YEL="" C_CYA="" C_DIM="" C_BLD="" C_OFF=""
fi
info() { printf '%s•%s %s\n' "$C_CYA" "$C_OFF" "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
err()  { printf '%s✗%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()  { err "$*"; exit 1; }
hdr()  { printf '\n%s%s%s\n' "$C_BLD" "$*" "$C_OFF"; }

cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT
trap 'err "unexpected error at line $LINENO (exit code $?)"' ERR

usage() {
  cat <<EOF
${C_BLD}selfsteal${C_OFF} ${VERSION} — camouflage website for a Reality self-steal node

Usage: selfsteal.sh [@] <command> [options]

Commands:
  install            install or re-apply the site (idempotent)
  update [--to TAG]  fetch a newer installer release and re-apply the site
  uninstall          stop and remove the site (--purge also removes certificates)
  status             show state, container, listeners and certificate
  logs               show Caddy logs (-f to follow, --tail N)
  restart            restart Caddy
  template [NAME]    switch the template without reinstalling
  domain [NAME]      switch the domain
  cert               discard and re-issue the certificate
  templates          list available templates
  prepare            only unpack a template for an EXISTING Caddy (no Docker, no ports, no firewall)

Options:
  --domain NAME      site / node host name (A/AAAA must point to this server)
  --template NAME    template to serve (see: selfsteal templates)
  --port N           loopback port for Xray's target (default ${DEFAULT_PORT})
  --email ADDR       contact e-mail for the certificate authority (optional)
  --staging          use the Let's Encrypt staging CA for this run only (for tests)
  --skip-dns-check   do not verify that the domain points to this server
  --no-ufw           do not touch the firewall
  --enable-ufw       install/enable ufw if needed (default: only add rules to an active ufw)
  --with-node        afterwards offer to run the node installer (remnanode.sh); off by default
  --seed STRING      randomization seed (default: derived from domain and machine-id)
  --purge            with uninstall: also delete certificates and volumes
  --out DIR          prepare: directory for the site files and the Caddy block
  --mode MODE        prepare: "public" (host on 443, default) or "node" (loopback port for Xray)
  -y, --yes          do not ask questions; fail if a required value is missing
  -h, --help         this help

Every option can also be given as SELFSTEAL_<NAME> (e.g. SELFSTEAL_DOMAIN).
Certificates are issued by HTTP-01 for exactly this domain; ports 80 must be reachable.
EOF
}

# ----------------------------------------------------------------- args -----
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain|--template|--port|--email|--seed|--to|--tail|--acme-ca|--acme-ca-root|--base-url|--out|--mode)
        [ $# -ge 2 ] || die "option $1 needs a value"
        set_opt "$1" "$2"; shift 2 ;;
      --domain=*|--template=*|--port=*|--email=*|--seed=*|--to=*|--tail=*|--acme-ca=*|--acme-ca-root=*|--base-url=*|--out=*|--mode=*)
        set_opt "${1%%=*}" "${1#*=}"; shift ;;
      --staging) STAGING=1; shift ;;
      --skip-dns-check) SKIP_DNS=1; shift ;;
      --no-ufw) NO_UFW=1; shift ;;
      --enable-ufw) ENABLE_UFW=1; shift ;;
      --with-node) WITH_NODE=1; shift ;;
      --purge) PURGE=1; shift ;;
      -f|--follow) FOLLOW=1; shift ;;
      -y|--yes) YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; ARGS+=("$@"); break ;;
      -*) die "unknown option: $1 (see --help)" ;;
      *) ARGS+=("$1"); shift ;;
    esac
  done
}
UPDATE_TO=""
set_opt() {
  case "$1" in
    --domain) DOMAIN="$2" ;;
    --template) TEMPLATE="$2" ;;
    --port) PORT="$2" ;;
    --email) ACME_EMAIL="$2" ;;
    --seed) SEED="$2" ;;
    --to) UPDATE_TO="$2" ;;
    --tail) TAIL="$2" ;;
    --acme-ca) ACME_CA="$2" ;;
    --acme-ca-root) ACME_CA_ROOT="$2" ;;
    --base-url) BASE_URL="$2" ;;
    --out) OUT_DIR="$2" ;;
    --mode) MODE="$2" ;;
  esac
}

# -------------------------------------------------------------- helpers -----
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root (sudo -i)"; }

ask() { # ask "Prompt" default  -> prints the answer
  local prompt=$1 def=${2:-} ans=""
  if [ "$YES" -eq 1 ] || [ ! -r /dev/tty ]; then printf '%s' "$def"; return 0; fi
  if [ -n "$def" ]; then read -r -p "$prompt [$def]: " ans </dev/tty || true
  else read -r -p "$prompt: " ans </dev/tty || true; fi
  printf '%s' "${ans:-$def}"
}
confirm() { # confirm "Question" -> 0 if yes (never auto-yes without --yes)
  local ans=""
  [ "$YES" -eq 1 ] && return 0
  [ -r /dev/tty ] || return 1
  read -r -p "$1 [y/N]: " ans </dev/tty || true
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

check_os() {
  [ -r /etc/os-release ] || die "cannot detect the operating system"
  local id="" ver=""
  # shellcheck source=/dev/null
  id=$(. /etc/os-release && printf '%s' "${ID:-}")
  # shellcheck source=/dev/null
  ver=$(. /etc/os-release && printf '%s' "${VERSION_ID:-0}")
  case "$id" in
    debian) version_ge "$ver" 12 || die "Debian 12 or newer is required (found $ver)" ;;
    ubuntu) version_ge "$ver" 22.04 || die "Ubuntu 22.04 or newer is required (found $ver)" ;;
    *) die "unsupported OS '$id' (Debian 12+ or Ubuntu 22.04+)" ;;
  esac
  ok "OS: $id $ver"
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::=--force-confold "$@" >/dev/null
}

ensure_tools() {
  local missing=() c
  for c in curl tar sha256sum awk openssl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  command -v ss >/dev/null 2>&1 || missing+=(iproute2)
  command -v getent >/dev/null 2>&1 || missing+=(libc-bin)
  if [ "${#missing[@]}" -gt 0 ]; then
    info "installing helper packages: ${missing[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
    local pk=()
    for c in "${missing[@]}"; do
      case "$c" in sha256sum) pk+=(coreutils) ;; awk) pk+=(mawk) ;; *) pk+=("$c") ;; esac
    done
    apt_install ca-certificates "${pk[@]}"
  fi
}

docker_ready() { docker info >/dev/null 2>&1; }
compose_ready() { docker compose version >/dev/null 2>&1; }

add_docker_repo() {
  local id codename
  # shellcheck source=/dev/null
  id=$(. /etc/os-release && printf '%s' "$ID")
  # shellcheck source=/dev/null
  codename=$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")
  DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
  apt_install ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl --proto '=https' --tlsv1.2 -fsSL "https://download.docker.com/linux/$id/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
    "$(dpkg --print-architecture)" "$id" "$codename" > /etc/apt/sources.list.d/docker.list
  DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
}

start_docker() {
  systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do docker_ready && return 0; sleep 1; done
  die "Docker is installed but the daemon is not running"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    docker_ready || start_docker
    if ! compose_ready; then
      info "installing the docker compose plugin"
      add_docker_repo
      apt_install docker-compose-plugin
    fi
  else
    info "installing Docker (official apt repository)"
    add_docker_repo
    apt_install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    start_docker
  fi
  compose_ready || die "docker compose plugin is not available"
  ok "Docker: $(docker --version | cut -d, -f1), $(docker compose version --short 2>/dev/null || echo compose)"
}

compose() { (cd "$APP_DIR" && docker compose "$@"); }

# ---------------------------------------------------------------- state -----
load_state() {
  if [ -r "$STATE_FILE" ]; then
    local s_domain="" s_template="" s_port="" s_seed="" s_ts="" s_ca="" s_root="" s_email=""
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    s_domain=${S_DOMAIN:-}; s_template=${S_TEMPLATE:-}; s_port=${S_PORT:-}; s_seed=${S_SEED:-}
    s_ts=${S_TS:-}; s_ca=${S_ACME_CA:-}; s_root=${S_ACME_CA_ROOT:-}; s_email=${S_EMAIL:-}
    DOMAIN=${DOMAIN:-$s_domain}; TEMPLATE=${TEMPLATE:-$s_template}; PORT=${PORT:-$s_port}
    SEED=${SEED:-$s_seed}; FIRST_TS=${s_ts:-}; ACME_CA=${ACME_CA:-$s_ca}; ACME_CA_ROOT=${ACME_CA_ROOT:-$s_root}
    ACME_EMAIL=${ACME_EMAIL:-$s_email}
    STATE_LOADED=1
  fi
}
STATE_LOADED=0
FIRST_TS=""

save_state() {
  mkdir -p "$APP_DIR"
  {
    printf 'S_VERSION=%q\n' "$VERSION"
    printf 'S_DOMAIN=%q\n' "$DOMAIN"
    printf 'S_TEMPLATE=%q\n' "$TEMPLATE"
    printf 'S_PORT=%q\n' "$PORT"
    printf 'S_SEED=%q\n' "$SEED"
    printf 'S_TS=%q\n' "$FIRST_TS"
    printf 'S_ACME_CA=%q\n' "$ACME_CA"
    printf 'S_ACME_CA_ROOT=%q\n' "$ACME_CA_ROOT"
    printf 'S_EMAIL=%q\n' "$ACME_EMAIL"
  } > "$STATE_FILE.new"
  chmod 600 "$STATE_FILE.new"
  mv "$STATE_FILE.new" "$STATE_FILE"
}

# ----------------------------------------------------------- validation -----
valid_domain() {
  [[ "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$ ]] && [ "${#1}" -le 253 ]
}
valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ] || return 1
}
valid_template() {
  local t
  for t in $TEMPLATE_NAMES; do [ "$t" = "$1" ] && return 0; done
  return 1
}

suggest_template() {
  case "$1" in
    *.cdn.*|cdn.*) echo cdn ;;
    *.api.*|api.*) echo api ;;
    *.s3.*|s3.*|*.storage.*|storage.*) echo storage ;;
    *.registry.*|registry.*) echo registry ;;
    docs.*|*.docs.*) echo docs ;;
    status.*) echo status ;;
    console.*|auth.*) echo console ;;
    *) echo default ;;
  esac
}

list_templates() {
  local t
  printf '%s\n' "Available templates:"
  for t in $TEMPLATE_NAMES; do printf '  %-10s %s\n' "$t" "$(template_desc "$t")"; done
}

# ------------------------------------------------------------------ dns -----
local_ips() { ip -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1; }

dns_check() {
  local d=$1 a4 a6 ips pub="" ip match=0
  if [ "$SKIP_DNS" -eq 1 ]; then warn "DNS check skipped"; return 0; fi
  a4=$(getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | sort -u || true)
  # getent may return IPv4-mapped addresses (::ffff:a.b.c.d) when there is no AAAA record: ignore them
  a6=$(getent ahostsv6 "$d" 2>/dev/null | awk '{print $1}' | grep -vi '^::ffff:' | sort -u || true)
  [ -n "$a4$a6" ] || die "$d does not resolve. Create an A record pointing to this server first (or use --skip-dns-check)."
  ips=$(local_ips)
  for ip in $a4 $a6; do
    if printf '%s\n' "$ips" | grep -qxF "$ip"; then match=1; fi
  done
  if [ "$match" -eq 0 ]; then
    pub=$(curl -4 -fsS --max-time 6 https://api.ipify.org 2>/dev/null || true)
    for ip in $a4; do [ -n "$pub" ] && [ "$ip" = "$pub" ] && match=1; done
  fi
  if [ "$match" -eq 0 ]; then
    die "$d resolves to $(printf '%s %s' "$a4" "$a6" | tr '\n' ' ') which is not an address of this server${pub:+ (public IP $pub)}. Fix the DNS record or use --skip-dns-check."
  fi
  if [ -n "$a6" ]; then
    local m6=0
    for ip in $a6; do printf '%s\n' "$ips" | grep -qxF "$ip" && m6=1; done
    [ "$m6" -eq 1 ] || die "$d has an AAAA record ($(printf '%s' "$a6" | tr '\n' ' ')) that is not on this server; the CA would validate over IPv6 and fail. Remove it or point it here."
  fi
  ok "DNS: $d points to this server"
}

port_busy() { ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .; }

check_ports() {
  local running=0
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then running=1; fi
  if [ "$running" -eq 0 ]; then
    port_busy 80 && die "port 80 is already in use (needed for certificate issuance): $(ss -H -ltnp 'sport = :80' | head -n1)"
    port_busy "$PORT" && die "loopback port $PORT is already in use: $(ss -H -ltnp "sport = :$PORT" | head -n1)"
  fi
  if port_busy 443; then info "port 443 is in use — expected: the node (Xray) owns it, the site stays on 127.0.0.1:$PORT"
  else warn "nothing listens on 443 yet; Xray must be configured to use 127.0.0.1:$PORT as its target"; fi
  ok "ports: 80 and 127.0.0.1:$PORT are available"
}

# ------------------------------------------------------------- download -----
release_base() {
  if [ -n "$BASE_URL" ]; then printf '%s' "${BASE_URL%/}"; return; fi
  [ "$VERSION" != "dev" ] || die "this is a development copy without pinned checksums; use a release build"
  [ -n "$REPO" ] || die "repository is not configured in this build"
  printf 'https://github.com/%s/releases/download/v%s' "$REPO" "$VERSION"
}

fetch() { # fetch URL OUT
  local proto="=https"
  case "$1" in http://127.0.0.1*|http://localhost*) proto="=https,http" ;; esac
  curl --proto "$proto" --tlsv1.2 -fsSL --retry 3 --connect-timeout 15 --max-time 180 -o "$2" "$1"
}

fetch_template() { # fetch_template NAME -> extracted dir in $TMP/tpl
  local name=$1 want got archive entries
  want=$(template_sha256 "$name")
  [ -n "$want" ] || die "no pinned checksum for template '$name' in this build"
  archive="$TMP/template-$name.tar.gz"
  info "downloading template '$name' (v$VERSION)"
  fetch "$(release_base)/template-$name.tar.gz" "$archive" || die "download failed: $(release_base)/template-$name.tar.gz"
  got=$(sha256sum "$archive" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then die "checksum mismatch for template-$name.tar.gz (expected $want, got $got) — refusing to use it"; fi
  ok "checksum verified ($got)"
  entries=$(tar -tzf "$archive")
  if printf '%s\n' "$entries" | grep -qE '(^/|(^|/)\.\.(/|$))'; then die "unsafe path inside the archive"; fi
  rm -rf "$TMP/tpl"; mkdir -p "$TMP/tpl"
  tar -xzf "$archive" -C "$TMP/tpl" --strip-components=1 --no-same-owner
  [ -d "$TMP/tpl/site" ] && [ -f "$TMP/tpl/Caddyfile.snippet" ] && [ -f "$TMP/tpl/randomize.sh" ] || die "archive has an unexpected layout"
}

# ---------------------------------------------------------------- apply -----
write_if_changed() { # write_if_changed FILE  (content on stdin)
  local f=$1 new
  new=$(mktemp "$TMP/w.XXXXXX")
  cat > "$new"
  if [ -f "$f" ] && cmp -s "$new" "$f"; then rm -f "$new"; return 0; fi
  if [ -f "$f" ]; then cat "$new" > "$f"; else chmod 644 "$new"; mv "$new" "$f"; fi
  rm -f "$new"
  NEED_RESTART=1
}

render_compose() {
  local ca_mount=""
  [ -f "$APP_DIR/acme-ca.pem" ] && ca_mount="      - ./acme-ca.pem:/etc/caddy/acme-ca.pem:ro"
  cat <<EOF
services:
  caddy:
    image: ${CADDY_IMAGE}
    container_name: ${CONTAINER}
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./snippet.caddy:/etc/caddy/snippet.caddy:ro
      - ./site:/var/www/html:ro
      - ./logs:/var/log/caddy
${ca_mount:-      # (no custom CA)}
      - caddy_data:/data
      - caddy_config:/config
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
volumes:
  caddy_data:
  caddy_config:
EOF
}

render_caddyfile() {
  local ca_line="" roots_line="" email_line=""
  if [ -n "$ACME_CA" ]; then ca_line=$'\t\t\tdir '"$ACME_CA"$'\n'
  elif [ "$STAGING" -eq 1 ]; then ca_line=$'\t\t\tdir https://acme-staging-v02.api.letsencrypt.org/directory\n'; fi
  [ -f "$APP_DIR/acme-ca.pem" ] && roots_line=$'\t\t\ttrusted_roots /etc/caddy/acme-ca.pem\n'
  [ -n "$ACME_EMAIL" ] && email_line=$'\t\t\temail '"$ACME_EMAIL"$'\n'
  cat <<EOF
{
	admin off
	http_port 80
	https_port ${PORT}
	auto_https disable_redirects
	servers {
		protocols h1 h2
	}
}

# plain HTTP: certificate challenges are answered by Caddy itself, everything else is redirected
:80 {
	header -Server
	redir https://${DOMAIN}{uri} permanent
}

# the site: reachable on loopback only, Xray forwards to it
${DOMAIN}:${PORT} {
	bind 127.0.0.1
	tls {
		issuer acme {
${ca_line}${roots_line}${email_line}			disable_tlsalpn_challenge
		}
	}
	import /etc/caddy/snippet.caddy
}
EOF
}

sync_site() { # sync_site SRC_DIR [DST_DIR] -> copies in place so a bind mount keeps working
  local src=$1 dst=${2:-$APP_DIR/site}
  mkdir -p "$dst"
  find "$dst" -mindepth 1 -delete
  cp -a "$src"/. "$dst"/
}

apply_template() { # needs $TMP/tpl extracted
  [ -n "$FIRST_TS" ] || FIRST_TS=$(date +%s)
  if [ -z "$SEED" ]; then
    SEED=$(printf '%s' "$DOMAIN:$(cat /etc/machine-id 2>/dev/null || hostname)" | sha256sum | cut -d' ' -f1)
  fi
  bash "$TMP/tpl/randomize.sh" --dir "$TMP/tpl" --seed "$SEED" --domain "$DOMAIN" --now "$FIRST_TS"
  mkdir -p "$APP_DIR/logs"
  sync_site "$TMP/tpl/site"
  write_if_changed "$APP_DIR/snippet.caddy" < "$TMP/tpl/Caddyfile.snippet"
}

write_configs() {
  # these values are written into the Caddyfile: accept only plain characters
  if [ -n "$ACME_EMAIL" ] && ! [[ "$ACME_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; then die "invalid e-mail address: $ACME_EMAIL"; fi
  if [ -n "$ACME_CA" ] && ! [[ "$ACME_CA" =~ ^https://[A-Za-z0-9._:/-]+$ ]]; then die "invalid ACME directory URL: $ACME_CA"; fi
  mkdir -p "$APP_DIR"
  if [ -n "$ACME_CA_ROOT" ]; then
    [ -r "$ACME_CA_ROOT" ] || die "cannot read $ACME_CA_ROOT"
    if [ "$ACME_CA_ROOT" != "$APP_DIR/acme-ca.pem" ]; then cp "$ACME_CA_ROOT" "$APP_DIR/acme-ca.pem"; fi
    ACME_CA_ROOT="$APP_DIR/acme-ca.pem"
  fi
  render_caddyfile | write_if_changed "$APP_DIR/Caddyfile"
  render_compose | write_if_changed "$APP_DIR/docker-compose.yml"
}

validate_config() {
  info "validating the Caddy configuration"
  local mounts=(-v "$APP_DIR/Caddyfile:/etc/caddy/Caddyfile:ro" -v "$APP_DIR/snippet.caddy:/etc/caddy/snippet.caddy:ro" -v "$APP_DIR/site:/var/www/html:ro")
  [ -f "$APP_DIR/acme-ca.pem" ] && mounts+=(-v "$APP_DIR/acme-ca.pem:/etc/caddy/acme-ca.pem:ro")
  local out
  if ! out=$(docker run --rm --network host "${mounts[@]}" "$CADDY_IMAGE" caddy validate --config /etc/caddy/Caddyfile 2>&1); then
    printf '%s\n' "$out" | grep -E '"level":"(error|fatal)"|Error' | tail -n 5 >&2
    die "the generated Caddy configuration is invalid (see above)"
  fi
}

start_site() {
  info "starting Caddy"
  if ! docker pull -q "$CADDY_IMAGE" >/dev/null 2>&1; then
    docker image inspect "$CADDY_IMAGE" >/dev/null 2>&1 || die "cannot pull $CADDY_IMAGE"
  fi
  validate_config
  local was_running=0
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ] && was_running=1
  compose up -d --remove-orphans >/dev/null
  if [ "$was_running" -eq 1 ]; then
    if [ "$NEED_RESTART" -eq 1 ]; then
      compose restart caddy >/dev/null
    elif [ "$(probe_site)" = "000" ]; then
      info "no certificate yet — restarting Caddy to retry issuance now"
      compose restart caddy >/dev/null
    fi
  fi
  NEED_RESTART=0
}

probe_site() { # prints the HTTP status, or 000 while the certificate is missing
  curl -ksS -o /dev/null -w '%{http_code}' --max-time 5 --resolve "$DOMAIN:$PORT:127.0.0.1" "https://$DOMAIN:$PORT/" 2>/dev/null || true
}

wait_ready() {
  info "waiting for the certificate (HTTP-01 for $DOMAIN)…"
  local code tries=$(( ${SELFSTEAL_READY_TIMEOUT:-150} / 2 ))
  [ "$tries" -ge 1 ] || tries=1
  for _ in $(seq 1 "$tries"); do
    code=$(probe_site)
    if [ -n "$code" ] && [ "$code" != "000" ]; then ok "site answers on 127.0.0.1:$PORT (HTTP $code)"; return 0; fi
    sleep 2
  done
  err "the site did not become ready in time. Errors reported by Caddy:"
  compose logs --no-color caddy 2>&1 | grep -E '"level":"(error|fatal)"' | tail -n 6 >&2 || true
  die "check that port 80 is reachable from the internet and that $DOMAIN points here"
}

cert_info() {
  echo | openssl s_client -connect "127.0.0.1:$PORT" -servername "$DOMAIN" 2>/dev/null \
    | openssl x509 -noout -subject -issuer -enddate 2>/dev/null || true
}

# ------------------------------------------------------------- firewall -----
ssh_ports() {
  local p
  p=$(ss -H -ltnp 2>/dev/null | awk '/"sshd"/ {n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')
  printf '%s' "${p:-22}"
}

configure_ufw() {
  if [ "$NO_UFW" -eq 1 ]; then info "firewall: skipped (--no-ufw)"; return 0; fi
  if ! command -v ufw >/dev/null 2>&1; then
    if [ "$ENABLE_UFW" -eq 1 ]; then apt_install ufw
    else info "firewall: ufw is not installed — not touching the firewall (use --enable-ufw to set it up)"; return 0; fi
  fi
  local p
  for p in $(ssh_ports); do ufw allow "$p/tcp" >/dev/null; done
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  if ufw status | grep -q '^Status: active'; then
    ok "firewall: ssh ($(ssh_ports)), 80 and 443 allowed (existing rules untouched)"
  elif [ "$ENABLE_UFW" -eq 1 ]; then
    ufw --force enable >/dev/null
    ok "firewall: ufw enabled with ssh ($(ssh_ports)), 80, 443"
  else
    warn "ufw is installed but inactive: rules for ssh, 80 and 443 were added; enable it yourself after checking: ufw enable"
  fi
}

# -------------------------------------------------------------- summary -----
print_summary() {
  hdr "Site is up"
  printf '  domain     : %s\n  template   : %s\n  listening  : 127.0.0.1:%s (TLS)\n  directory  : %s\n' "$DOMAIN" "$TEMPLATE" "$PORT" "$APP_DIR"
  hdr "Values for the panel (Reality profile of this node)"
  printf '  serverNames : ["%s"]\n  target/dest : "127.0.0.1:%s"\n  xver        : 0\n' "$DOMAIN" "$PORT"
  hdr "Xray inbound fragment (merge into your profile)"
  cat <<EOF
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "target": "127.0.0.1:${PORT}",
      "xver": 0,
      "serverNames": ["${DOMAIN}"],
      "privateKey": "<x25519 private key from the panel>",
      "shortIds": ["<short id>"]
    }
  }
EOF
  printf '\n%sThe node itself is configured in the panel; this script did not modify it.%s\n' "$C_DIM" "$C_OFF"
}

install_self() {
  if [ "$0" -ef "$BIN_PATH" ]; then return 0; fi
  if [ -f "$0" ] && [ -r "$0" ] && [ "$(basename "$0")" != "bash" ]; then
    install -m 0755 "$0" "$BIN_PATH"
  else
    fetch "$(release_base)/selfsteal.sh" "$TMP/self.sh" || { warn "could not install the 'selfsteal' command"; return 0; }
    bash -n "$TMP/self.sh" || { warn "downloaded installer is invalid; not installing the command"; return 0; }
    install -m 0755 "$TMP/self.sh" "$BIN_PATH"
  fi
  ok "command installed: selfsteal ($BIN_PATH)"
}

# ------------------------------------------------------------- commands -----
require_installed() { [ -r "$STATE_FILE" ] || die "not installed (run: selfsteal install)"; }

resolve_inputs() { # fill DOMAIN/TEMPLATE/PORT from args, state or prompts
  [ -n "$PORT" ] || PORT=$DEFAULT_PORT
  if [ -z "$DOMAIN" ]; then
    DOMAIN=$(ask "Domain of this node's site (e.g. se1.cdn.example.com)" "")
  fi
  DOMAIN=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')
  [ -n "$DOMAIN" ] || die "domain is required (--domain NAME)"
  valid_domain "$DOMAIN" || die "invalid domain: $DOMAIN"
  if [ -z "$TEMPLATE" ]; then
    if [ "$YES" -eq 0 ] && [ -r /dev/tty ]; then list_templates >&2; fi
    TEMPLATE=$(ask "Template" "$(suggest_template "$DOMAIN")")
  fi
  valid_template "$TEMPLATE" || die "unknown template '$TEMPLATE' (see: selfsteal templates)"
  valid_port "$PORT" || die "invalid port: $PORT (use 1024-65535)"
}

cmd_install() {
  need_root
  hdr "selfsteal ${VERSION}: install"
  check_os
  ensure_tools
  load_state
  [ "$STATE_LOADED" -eq 1 ] && info "already installed — re-applying with the current settings"
  resolve_inputs
  dns_check "$DOMAIN"
  ensure_docker
  check_ports
  TMP=$(mktemp -d)
  fetch_template "$TEMPLATE"
  mkdir -p "$APP_DIR"
  apply_template
  write_configs
  save_state
  start_site
  wait_ready
  configure_ufw
  install_self
  print_summary
  if [ "$WITH_NODE" -eq 1 ]; then offer_node; fi
}

offer_node() {
  hdr "Node installer (optional)"
  warn "this downloads and runs a third-party script as root: DigneZzZ/remnawave-scripts remnanode.sh (not pinned, not verified by this installer)"
  if confirm "Run it now?"; then
    bash <(curl --proto '=https' --tlsv1.2 -fsSL https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh) @ install
  else
    info "skipped"
  fi
}

cmd_status() {
  need_root
  require_installed
  load_state
  hdr "selfsteal ${VERSION}: status"
  printf '  domain   : %s\n  template : %s\n  target   : 127.0.0.1:%s\n  seed     : %s…\n' "$DOMAIN" "$TEMPLATE" "$PORT" "${SEED:0:8}"
  if docker ps --format '{{.Names}} {{.Status}}' | grep -q "^$CONTAINER "; then
    printf '  caddy    : %s\n' "$(docker ps --format '{{.Names}} {{.Status}}' | grep "^$CONTAINER " | cut -d' ' -f2-)"
  else printf '  caddy    : not running\n'; fi
  printf '  listening:\n'
  ss -H -ltn "( sport = :80 or sport = :$PORT )" | awk '{print "    " $4}'
  printf '  certificate:\n'
  cert_info | sed 's/^/    /'
}

cmd_logs() {
  need_root; require_installed
  local a=(logs --no-color --tail "$TAIL")
  [ "$FOLLOW" -eq 1 ] && a+=(-f)
  compose "${a[@]}" caddy
}

cmd_restart() { need_root; require_installed; compose restart caddy >/dev/null; ok "restarted"; }

cmd_template() {
  need_root; require_installed; load_state
  [ "${#ARGS[@]}" -ge 1 ] && TEMPLATE=${ARGS[0]}
  [ "${#ARGS[@]}" -ge 1 ] || { list_templates; TEMPLATE=$(ask "Template" "$TEMPLATE"); }
  valid_template "$TEMPLATE" || die "unknown template '$TEMPLATE'"
  TMP=$(mktemp -d)
  fetch_template "$TEMPLATE"
  apply_template
  write_configs
  save_state
  start_site
  wait_ready
  ok "template switched to '$TEMPLATE'"
}

cmd_domain() {
  need_root; require_installed
  local old_domain
  load_state
  old_domain=$DOMAIN
  if [ "${#ARGS[@]}" -ge 1 ]; then DOMAIN=${ARGS[0]}; else DOMAIN=$(ask "New domain" ""); fi
  DOMAIN=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')
  valid_domain "$DOMAIN" || die "invalid domain: $DOMAIN"
  [ "$DOMAIN" != "$old_domain" ] || { info "domain is already $DOMAIN"; return 0; }
  dns_check "$DOMAIN"
  SEED=""
  TMP=$(mktemp -d)
  fetch_template "$TEMPLATE"
  apply_template
  write_configs
  save_state
  start_site
  wait_ready
  ok "domain switched to $DOMAIN — update serverNames in the panel"
  printf '  serverNames : ["%s"]\n' "$DOMAIN"
}

cmd_cert() {
  need_root; require_installed; load_state
  valid_domain "$DOMAIN" || die "invalid domain in state"
  warn "discarding the stored certificate for $DOMAIN and requesting a new one"
  compose stop caddy >/dev/null
  compose run --rm --no-deps --entrypoint sh caddy -c "rm -rf /data/caddy/certificates/*/$DOMAIN" >/dev/null
  compose up -d >/dev/null
  wait_ready
  cert_info | sed 's/^/  /'
}

cmd_update() {
  need_root; require_installed
  local tag="${UPDATE_TO:-}" url
  if [ -z "$tag" ]; then
    [ -n "$REPO" ] || die "repository is not configured in this build; use --to TAG with SELFSTEAL_BASE_URL"
    url=$(curl --proto '=https' -fsSI -o /dev/null -w '%{redirect_url}' "https://github.com/$REPO/releases/latest" || true)
    tag=${url##*/}
    [ -n "$tag" ] || die "could not determine the latest release"
  fi
  tag=${tag#v}
  [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version: $tag"
  if [ "$tag" = "$VERSION" ]; then info "already at v$VERSION — re-applying"; else info "updating v$VERSION → v$tag"; fi
  TMP=$(mktemp -d)
  local base="${BASE_URL:-https://github.com/$REPO/releases/download/v$tag}"
  fetch "${base%/}/selfsteal.sh" "$TMP/new.sh" || die "could not download the installer for v$tag"
  bash -n "$TMP/new.sh" || die "downloaded installer is not a valid script"
  grep -q "^VERSION=\"$tag\"" "$TMP/new.sh" || die "downloaded installer does not match v$tag"
  install -m 0755 "$TMP/new.sh" "$BIN_PATH"
  ok "installer updated"
  exec "$BIN_PATH" apply --yes
}

cmd_apply() { # internal: re-apply the saved configuration with this installer version
  need_root; require_installed; load_state
  YES=1
  TMP=$(mktemp -d)
  fetch_template "$TEMPLATE"
  apply_template
  write_configs
  save_state
  start_site
  wait_ready
  ok "applied v$VERSION"
}

cmd_prepare() {
  local c h primary stamp snippet
  local hosts=()
  [ -n "$OUT_DIR" ] || die "--out DIR is required"
  [ -n "$TEMPLATE" ] || die "--template NAME is required (see: selfsteal templates)"
  valid_template "$TEMPLATE" || die "unknown template '$TEMPLATE'"
  [ -n "$DOMAIN" ] || die "--domain HOST[,ALIAS...] is required"
  IFS=',' read -r -a hosts <<< "$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
  for h in "${hosts[@]}"; do valid_domain "$h" || die "invalid domain: $h"; done
  primary=${hosts[0]}
  DOMAIN=$primary
  case "$MODE" in public|node) ;; *) die "--mode must be 'public' or 'node'" ;; esac
  [ -n "$PORT" ] || PORT=$DEFAULT_PORT
  [ "$MODE" = "public" ] || valid_port "$PORT" || die "invalid port: $PORT"
  for c in curl tar sha256sum awk; do command -v "$c" >/dev/null 2>&1 || die "'$c' is required"; done

  TMP=$(mktemp -d)
  fetch_template "$TEMPLATE"
  mkdir -p "$OUT_DIR"
  OUT_DIR=$(cd "$OUT_DIR" && pwd)
  stamp="$OUT_DIR/.selfsteal-stamp-$primary"
  if [ -f "$stamp" ]; then FIRST_TS=$(cat "$stamp"); else FIRST_TS=$(date +%s); printf '%s\n' "$FIRST_TS" > "$stamp"; fi
  if [ -z "$SEED" ]; then
    SEED=$(printf '%s' "$primary:$(cat /etc/machine-id 2>/dev/null || hostname)" | sha256sum | cut -d' ' -f1)
  fi
  bash "$TMP/tpl/randomize.sh" --dir "$TMP/tpl" --seed "$SEED" --domain "$primary" --now "$FIRST_TS"
  sync_site "$TMP/tpl/site" "$OUT_DIR/site/$primary"
  snippet=$(sed "s|^root \* /var/www/html\$|root * $OUT_DIR/site/$primary|" "$TMP/tpl/Caddyfile.snippet" | sed 's/^/\t/')
  {
    printf '# generated by selfsteal prepare: template %s, release v%s — do not edit, re-run prepare instead\n' "$TEMPLATE" "$VERSION"
    if [ "$MODE" = "public" ]; then
      printf '%s {\n' "$(IFS=,; printf '%s' "${hosts[*]}" | sed 's/,/, /g')"
    else
      printf '%s:%s {\n\tbind 127.0.0.1\n\ttls {\n\t\tissuer acme {\n\t\t\tdisable_tlsalpn_challenge\n\t\t}\n\t}\n' "$primary" "$PORT"
    fi
    printf '%s\n}\n' "$snippet"
  } > "$OUT_DIR/$primary.caddy"
  chmod -R a+rX "$OUT_DIR"
  ok "prepared '$TEMPLATE' for ${hosts[*]} in $OUT_DIR"
  printf '  site files : %s\n  Caddy block: %s\n' "$OUT_DIR/site/$primary" "$OUT_DIR/$primary.caddy"
  hdr "Next steps"
  printf '  1. make sure your Caddyfile contains:  import %s/*.caddy\n' "$OUT_DIR"
  if [ "$MODE" = "node" ]; then
    printf '  2. node mode also needs this in the global options block at the top of the Caddyfile:\n       auto_https disable_redirects\n'
    printf '     and Caddy must not listen on 443 (Xray owns it); port 80 must stay reachable for the certificate.\n'
    printf '  3. Xray target: 127.0.0.1:%s, serverNames: ["%s"], xver: 0\n' "$PORT" "$primary"
  else
    printf '  2. DNS A/AAAA records for %s must point to this server\n' "${hosts[*]}"
  fi
  printf '  %s. caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy\n' "$([ "$MODE" = node ] && echo 4 || echo 3)"
}

cmd_uninstall() {
  need_root; require_installed; load_state
  warn "this stops the site for $DOMAIN and removes $APP_DIR"
  confirm "Continue?" || die "cancelled"
  if [ -f "$APP_DIR/docker-compose.yml" ]; then
    if [ "$PURGE" -eq 1 ]; then compose down -v --remove-orphans >/dev/null 2>&1 || true
    else compose down --remove-orphans >/dev/null 2>&1 || true; fi
  fi
  rm -rf "$APP_DIR"
  rm -f "$BIN_PATH"
  ok "removed. Firewall rules were left as they are."
  [ "$PURGE" -eq 1 ] || info "certificates are kept in the docker volume selfsteal_caddy_data (use --purge to delete)"
}

main() {
  [ "${1:-}" = "@" ] && shift
  local cmd=${1:-help}
  [ $# -gt 0 ] && shift
  parse_args "$@"
  case "$cmd" in
    install) cmd_install ;;
    update) cmd_update ;;
    uninstall|remove) cmd_uninstall ;;
    status) cmd_status ;;
    logs) cmd_logs ;;
    restart) cmd_restart ;;
    template) cmd_template ;;
    domain) cmd_domain ;;
    cert|renew-ssl) cmd_cert ;;
    apply) cmd_apply ;;
    templates|list) list_templates ;;
    prepare) cmd_prepare ;;
    help|-h|--help) usage ;;
    version|--version) echo "$VERSION" ;;
    *) err "unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
