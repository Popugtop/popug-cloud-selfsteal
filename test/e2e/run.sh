#!/usr/bin/env bash
# End-to-end test of installer/selfsteal.sh in a fresh Debian 12 container with its own Docker daemon,
# using Pebble (a test ACME server) so that certificates are really issued over HTTP-01.
#   test/e2e/run.sh        (needs Docker, network access; takes a few minutes)
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
C=popug-e2e
LOG="$root/docs/e2e/run.log"
mkdir -p "$root/docs/e2e"; : > "$LOG"
pass=0; fail=0
x() { docker exec "$C" bash -c "$*"; }
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
# check "description" 'shell command run inside the container (must succeed)'
check() {
  local d=$1; shift
  if out=$(x "$*" 2>&1); then pass=$((pass + 1)); say "  PASS  $d"; else fail=$((fail + 1)); say "  FAIL  $d"; printf '%s\n' "$out" | tail -n 15 | sed 's/^/        /' | tee -a "$LOG"; fi
}
# expect_fail "description" 'command' ['text that must appear in the output']
expect_fail() {
  local d=$1 cmd=$2 want=${3:-} out rc=0
  out=$(x "$cmd" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && { [ -z "$want" ] || printf '%s' "$out" | grep -qF -- "$want"; }; then pass=$((pass + 1)); say "  PASS  $d"
  else fail=$((fail + 1)); say "  FAIL  $d (rc=$rc)"; printf '%s\n' "$out" | tail -n 10 | sed 's/^/        /' | tee -a "$LOG"; fi
}
run() { say "\$ $*"; x "$*" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -n "${LINES_MAX:-40}" | tee -a "$LOG"; }

ENVV='SELFSTEAL_BASE_URL=http://127.0.0.1:8099'
ACME='--acme-ca https://localhost:14000/dir --acme-ca-root /root/pebble.minica.pem --skip-dns-check --yes'
D1=se1.cdn.popug.cloud

say "== build release"; (cd "$root" && node tools/build-release.mjs --repo acme/popug-cloud-selfsteal | tail -1) | tee -a "$LOG"

say "== start a clean Debian 12 container (no Docker inside)"
docker rm -f "$C" >/dev/null 2>&1 || true
docker volume rm -f popug-e2e-docker >/dev/null
docker run -d --name "$C" --privileged -v popug-e2e-docker:/var/lib/docker \
  -v "$root/release:/release:ro" -v "$root/.work/pebble.minica.pem:/root/pebble.minica.pem:ro" \
  -v "$root/test/e2e/pebble-config.json:/root/pebble-config.json:ro" popug-e2e sleep infinity >/dev/null
x 'cp -r /release /release-bad && printf X | dd of=/release-bad/template-api.tar.gz bs=1 seek=100 conv=notrunc 2>/dev/null
   nohup python3 -m http.server 8099 --bind 127.0.0.1 -d /release >/tmp/http1.log 2>&1 &
   nohup python3 -m http.server 8098 --bind 127.0.0.1 -d /release-bad >/tmp/http2.log 2>&1 &
   sleep 1'
check "docker is NOT installed yet" '! command -v docker'

say "== argument handling"
check "--help works" "bash /release/selfsteal.sh --help | grep -q 'Usage: selfsteal.sh'"
check "templates are listed" "bash /release/selfsteal.sh templates | grep -q 'storage'"
expect_fail "invalid domain is rejected" "$ENVV bash /release/selfsteal.sh @ install --yes --domain 'Bad_Domain!' --template cdn" "invalid domain"
expect_fail "unknown template is rejected" "$ENVV bash /release/selfsteal.sh @ install --yes --domain a.b.example.com --template nope" "unknown template"
expect_fail "unknown option is rejected" "bash /release/selfsteal.sh @ install --bogus" "unknown option"
expect_fail "DNS check fails for an unresolvable name" "$ENVV bash /release/selfsteal.sh @ install --yes --domain nothere.invalid.example --template cdn" "does not resolve"

say "== first install: Docker gets installed; no ACME server yet, so the site cannot become ready"
LINES_MAX=14 run "$ENVV SELFSTEAL_READY_TIMEOUT=6 bash /release/selfsteal.sh @ install --domain $D1 --template cdn $ACME || true"
check "Docker was installed by the installer" 'docker info >/dev/null 2>&1 && docker compose version >/dev/null'
check "state file and compose file exist" 'test -f /opt/selfsteal/state.env && test -f /opt/selfsteal/docker-compose.yml'
check "Caddy container is running" 'docker ps --format "{{.Names}}" | grep -qx selfsteal-caddy'

say "== start the test ACME server (Pebble)"
# shellcheck disable=SC2016  # runs inside the container, expansions are intended there
x 'docker run -d --name challtestsrv --network host ghcr.io/letsencrypt/pebble-challtestsrv:latest -defaultIPv6 "" -defaultIPv4 127.0.0.1 -http01 "" -https01 "" -tlsalpn01 "" >/dev/null
   docker run -d --name pebble --network host -e PEBBLE_VA_NOSLEEP=1 -v /root/pebble-config.json:/test/config/pebble-config.json ghcr.io/letsencrypt/pebble:latest -config /test/config/pebble-config.json -dnsserver 127.0.0.1:8053 >/dev/null
   for i in $(seq 1 40); do curl -sk https://localhost:14000/dir >/dev/null && exit 0; sleep 1; done; exit 1' >>"$LOG" 2>&1
check "Pebble answers" 'curl -sk https://localhost:14000/dir | grep -q newOrder'
x 'curl -sk https://localhost:15000/roots/0 > /root/pebble-root.pem'

say "== re-run install (idempotent; must retry issuance and succeed)"
LINES_MAX=40 run "$ENVV bash /release/selfsteal.sh @ install --domain $D1 --template cdn $ACME"
CURLV="curl -s --cacert /root/pebble-root.pem --resolve $D1:8443:127.0.0.1"
check "valid certificate chain and name on 127.0.0.1:8443" "$CURLV -o /dev/null https://$D1:8443/"
check "cdn template: 404 page at /" "[ \"\$($CURLV -o /dev/null -w '%{http_code}' https://$D1:8443/)\" = 404 ]"
check "no Server header (200 and 404)" "! $CURLV -I https://$D1:8443/robots.txt | grep -qi '^server:' && ! $CURLV -I https://$D1:8443/nope | grep -qi '^server:'"
check "HTTPS listener is bound to 127.0.0.1 only" "ss -ltn | grep -q '127.0.0.1:8443' && ! ss -ltn | grep -E '(0.0.0.0|\\*|\\[::\\]):8443'"
check "port 80 is listening" "ss -ltn | grep -qE '(0.0.0.0|\\*):80 '"
check "HTTP (any Host) redirects to https with 301, no Server header" "r=\$(curl -si -H 'Host: other.example' http://127.0.0.1/x); echo \"\$r\" | head -1 | grep -q 301 && echo \"\$r\" | grep -qi \"location: https://$D1/x\" && ! echo \"\$r\" | grep -qi '^server:'"
check "'selfsteal' command installed" 'test -x /usr/local/bin/selfsteal'
check "ufw rules added (ssh, 80, 443), firewall left inactive" 'ufw show added | grep -q "allow 80/tcp" && ufw show added | grep -q "allow 443/tcp" && ufw show added | grep -q "allow 22/tcp" && ufw status | grep -q inactive'
if grep -q 'serverNames : \["se1.cdn.popug.cloud"\]' "$LOG" && grep -q 'target/dest : "127.0.0.1:8443"' "$LOG" && grep -q '"xver": 0' "$LOG"; then pass=$((pass + 1)); say "  PASS  summary prints serverNames, target and xver"; else fail=$((fail + 1)); say "  FAIL  summary is missing panel values"; fi

say "== idempotency"
x 'cd /opt/selfsteal && (find site -type f -exec sha256sum {} + | sort; sha256sum Caddyfile snippet.caddy docker-compose.yml state.env) | sha256sum > /root/before.sum; docker inspect -f "{{.Id}} {{.State.StartedAt}}" selfsteal-caddy > /root/before.id'
LINES_MAX=6 run "$ENVV selfsteal install $ACME --domain $D1 --template cdn"
check "files unchanged after re-install" 'cd /opt/selfsteal && (find site -type f -exec sha256sum {} + | sort; sha256sum Caddyfile snippet.caddy docker-compose.yml state.env) | sha256sum | cmp - /root/before.sum'
check "container not restarted by re-install" 'docker inspect -f "{{.Id}} {{.State.StartedAt}}" selfsteal-caddy | cmp - /root/before.id'

say "== download integrity"
expect_fail "tampered archive is refused" "SELFSTEAL_BASE_URL=http://127.0.0.1:8098 selfsteal template api --yes" "checksum mismatch"
check "site unchanged after refused download" 'cd /opt/selfsteal && (find site -type f -exec sha256sum {} + | sort; sha256sum Caddyfile snippet.caddy docker-compose.yml state.env) | sha256sum | cmp - /root/before.sum'

say "== template switch"
LINES_MAX=5 run "$ENVV selfsteal template api --yes"
check "api template: / returns JSON ok" "$CURLV https://$D1:8443/ | grep -q '\"service\":\"popug-api\"'"
check "api template: /v1/x returns 401" "[ \"\$($CURLV -o /dev/null -w '%{http_code}' https://$D1:8443/v1/x)\" = 401 ]"
LINES_MAX=5 run "$ENVV selfsteal template storage --yes"
check "storage template: AccessDenied XML at /" "$CURLV https://$D1:8443/ | grep -q '<Code>AccessDenied</Code>'"
LINES_MAX=5 run "$ENVV selfsteal template cdn --yes"
check "back on cdn" "[ \"\$($CURLV -o /dev/null -w '%{http_code}' https://$D1:8443/)\" = 404 ]"
x "$CURLV https://$D1:8443/ | grep -o 'edge [0-9a-f]*' | head -1 > /root/e1.txt"

say "== domain switch"
D2=de1.cdn.popug.cloud
LINES_MAX=8 run "$ENVV selfsteal domain $D2 --skip-dns-check --yes"
check "new domain serves a valid certificate" "curl -s --cacert /root/pebble-root.pem --resolve $D2:8443:127.0.0.1 -o /dev/null https://$D2:8443/"
check "state has the new domain" "grep -q $D2 /opt/selfsteal/state.env"
check "randomization differs between domains (404 page)" "curl -s --cacert /root/pebble-root.pem --resolve $D2:8443:127.0.0.1 https://$D2:8443/ | grep -o 'edge [0-9a-f]*' | head -1 > /root/e2.txt; ! grep -q \"\$(cat /root/e2.txt)\" /root/e1.txt 2>/dev/null"

say "== certificate re-issue, status, logs, restart"
LINES_MAX=12 run "$ENVV selfsteal cert --yes"
check "certificate valid after re-issue" "curl -s --cacert /root/pebble-root.pem --resolve $D2:8443:127.0.0.1 -o /dev/null https://$D2:8443/"
LINES_MAX=25 run "selfsteal status"
check "status shows domain and certificate" "selfsteal status | grep -q $D2 && selfsteal status | grep -q 'notAfter'"
check "logs work" 'selfsteal logs --tail 3 | grep -q .'
check "restart works" 'selfsteal restart'

say "== update (re-apply from the installer of the same release)"
VER=$(node -p "require('$root/package.json').version")
LINES_MAX=8 run "$ENVV selfsteal update --to $VER --yes"
check "site still answers after update" "curl -s --cacert /root/pebble-root.pem --resolve $D2:8443:127.0.0.1 -o /dev/null https://$D2:8443/"

say "== uninstall"
LINES_MAX=6 run "selfsteal uninstall --yes --purge"
check "container removed" '! docker ps -a --format "{{.Names}}" | grep -qx selfsteal-caddy'
check "directory and command removed" '! test -e /opt/selfsteal && ! test -e /usr/local/bin/selfsteal'
check "volumes purged" '! docker volume ls -q | grep -q selfsteal'
check "Pebble containers untouched" 'docker ps --format "{{.Names}}" | grep -qx pebble'

say ""
say "RESULT: $pass passed, $fail failed"
docker rm -f "$C" >/dev/null 2>&1 || true
[ "$fail" -eq 0 ]
