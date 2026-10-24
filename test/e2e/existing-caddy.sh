#!/usr/bin/env bash
# `selfsteal prepare` against a Caddy installed with apt (not Docker): public mode (root server) and node mode.
#   test/e2e/existing-caddy.sh debian|cloudsmith
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
flavor=${1:-debian}
C=popug-apt
LOG="$root/docs/e2e/existing-caddy-$flavor.log"; mkdir -p "$root/docs/e2e"; : > "$LOG"
pass=0; fail=0
x() { docker exec "$C" bash -c "$*"; }
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
check() { local d=$1; shift
  if out=$(x "$*" 2>&1); then pass=$((pass + 1)); say "  PASS  $d"; else fail=$((fail + 1)); say "  FAIL  $d"; printf '%s\n' "$out" | tail -n 8 | sed 's/^/        /' | tee -a "$LOG"; fi; }

(cd "$root" && node tools/build-release.mjs --repo acme/popug-cloud-selfsteal >/dev/null)
docker rm -f "$C" pebble-apt challtest-apt >/dev/null 2>&1 || true
docker run -d --name "$C" -v "$root/release:/release:ro" -v "$root/.work/pebble.minica.pem:/root/pebble.minica.pem:ro" popug-e2e sleep infinity >/dev/null
docker run -d --name challtest-apt --network "container:$C" ghcr.io/letsencrypt/pebble-challtestsrv:latest -defaultIPv6 "" -defaultIPv4 127.0.0.1 -http01 "" -https01 "" -tlsalpn01 "" >/dev/null
docker run -d --name pebble-apt --network "container:$C" -e PEBBLE_VA_NOSLEEP=1 -v "$root/test/e2e/pebble-config.json:/test/config/pebble-config.json" ghcr.io/letsencrypt/pebble:latest -config /test/config/pebble-config.json -dnsserver 127.0.0.1:8053 >/dev/null
x 'nohup python3 -m http.server 8099 --bind 127.0.0.1 -d /release >/tmp/http.log 2>&1 & sleep 1'

say "== Caddy from apt ($flavor)"
if [ "$flavor" = cloudsmith ]; then
  x 'apt-get update -qq >/dev/null && apt-get install -y -qq gnupg debian-keyring debian-archive-keyring apt-transport-https >/dev/null
     curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
     curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt -o /etc/apt/sources.list.d/caddy-stable.list
     apt-get update -qq >/dev/null && apt-get install -y -qq caddy >/dev/null' >>"$LOG" 2>&1
else
  x 'apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq caddy >/dev/null' >>"$LOG" 2>&1
fi
say "  $(x 'caddy version')"
for _ in $(seq 1 40); do x 'curl -sk https://localhost:14000/dir' 2>/dev/null | grep -q newOrder && break; sleep 1; done
x 'curl -sk https://localhost:15000/roots/0 > /root/pebble-root.pem'

# the "existing" Caddyfile of a server that already hosts other things
x 'cat > /etc/caddy/Caddyfile <<EOT
{
	acme_ca https://localhost:14000/dir
	acme_ca_root /root/pebble.minica.pem
	auto_https disable_redirects
}
other.example.com {
	respond "existing site"
}
import /var/www/selfsteal/*.caddy
EOT'

PREP="SELFSTEAL_BASE_URL=http://127.0.0.1:8099 bash /release/selfsteal.sh @ prepare --out /var/www/selfsteal"
say "== prepare: root server (public mode)"
check "root + www alias"     "$PREP --template root --domain popug.cloud,www.popug.cloud >/dev/null"
check "docs"                 "$PREP --template docs --domain docs.popug.cloud >/dev/null"
check "status"               "$PREP --template status --domain status.popug.cloud >/dev/null"
check "console + auth alias" "$PREP --template console --domain console.popug.cloud,auth.popug.cloud >/dev/null"
check "api"                  "$PREP --template api --domain api.popug.cloud >/dev/null"
check "cdn"                  "$PREP --template cdn --domain cdn.popug.cloud >/dev/null"
check "storage (s3)"         "$PREP --template storage --domain s3.popug.cloud,storage.popug.cloud >/dev/null"
say "== prepare: node mode on the same Caddy"
check "cdn node block"       "$PREP --template cdn --domain se1.cdn.popug.cloud --mode node --port 8443 >/dev/null"
# shellcheck disable=SC2016  # runs inside the container
check "caddy validate (7 public sites + 1 node site)" 'out=$(caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1); echo "$out" | tail -n 6; echo "$out" | grep -qi "valid configuration"'
x 'nohup caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >/tmp/caddy.log 2>&1 & sleep 3'

CV() { printf 'curl -s --cacert /root/pebble-root.pem --resolve %s:%s:127.0.0.1' "$1" "$2"; }
wait_cert() { # wait_cert "description" host [port]
  local d=$1 h=$2 p=${3:-443}
  for _ in $(seq 1 60); do
    if x "$(CV "$h" "$p") -o /dev/null https://$h:$p/" >/dev/null 2>&1; then pass=$((pass + 1)); say "  PASS  $d"; return 0; fi
    sleep 1
  done
  fail=$((fail + 1)); say "  FAIL  $d"; x 'tail -n 8 /tmp/caddy.log' 2>&1 | sed 's/^/        /' | tee -a "$LOG"
}
say "== certificates over HTTP-01 and content"
for h in popug.cloud www.popug.cloud docs.popug.cloud status.popug.cloud console.popug.cloud auth.popug.cloud api.popug.cloud cdn.popug.cloud s3.popug.cloud storage.popug.cloud; do
  wait_cert "valid certificate: $h" "$h"
done
check "existing site still works" "$(CV other.example.com 443) --insecure https://other.example.com/ | grep -q 'existing site' || $(CV other.example.com 443) -k https://other.example.com/ | grep -q 'existing site'"
check "root landing"       "$(CV popug.cloud 443) https://popug.cloud/ | grep -q 'Storage, CDN and API'"
check "www alias serves the same"  "$(CV www.popug.cloud 443) https://www.popug.cloud/ | grep -q 'Storage, CDN and API'"
check "docs overview"      "$(CV docs.popug.cloud 443) https://docs.popug.cloud/ | grep -q 'Popug Cloud documentation'"
check "docs CLI page"      "$(CV docs.popug.cloud 443) https://docs.popug.cloud/cli/ | grep -q 'popug storage upload'"
check "status page"        "$(CV status.popug.cloud 443) https://status.popug.cloud/ | grep -q 'All systems operational'"
check "console sign-in"    "$(CV console.popug.cloud 443) https://console.popug.cloud/ | grep -q 'Sign in to Console'"
check "auth alias = console" "$(CV auth.popug.cloud 443) https://auth.popug.cloud/beta/ | grep -q 'invite-only'"
check "api JSON"           "$(CV api.popug.cloud 443) https://api.popug.cloud/ | grep -q '\"service\":\"popug-api\"'"
check "cdn root is 404"    "[ \"\$($(CV cdn.popug.cloud 443) -o /dev/null -w '%{http_code}' https://cdn.popug.cloud/)\" = 404 ]"
check "s3 AccessDenied"    "$(CV s3.popug.cloud 443) https://s3.popug.cloud/ | grep -q AccessDenied"
check "custom 404 on docs" "[ \"\$($(CV docs.popug.cloud 443) -o /dev/null -w '%{http_code}' https://docs.popug.cloud/nope)\" = 404 ] && $(CV docs.popug.cloud 443) https://docs.popug.cloud/nope | grep -q 'Page not found'"
check "no Server header on our sites" "! $(CV docs.popug.cloud 443) -I https://docs.popug.cloud/ | grep -qi '^server:' && ! $(CV docs.popug.cloud 443) -I https://docs.popug.cloud/nope | grep -qi '^server:' && ! $(CV api.popug.cloud 443) -I https://api.popug.cloud/ | grep -qi '^server:'"

say "== node mode"
wait_cert "node site: valid certificate on 127.0.0.1:8443" se1.cdn.popug.cloud 8443
check "node site bound to loopback only" "ss -ltn | grep -q '127.0.0.1:8443' && ! ss -ltn | grep -E '(0.0.0.0|\\*|\\[::\\]):8443'"
check "node site serves the cdn template" "[ \"\$($(CV se1.cdn.popug.cloud 8443) -o /dev/null -w '%{http_code}' https://se1.cdn.popug.cloud:8443/)\" = 404 ] && $(CV se1.cdn.popug.cloud 8443) https://se1.cdn.popug.cloud:8443/ | grep -q 'requested object was not found'"

say "== idempotent re-run and reload"
x 'cd /var/www/selfsteal && (find . -type f ! -name ".selfsteal-stamp*" -exec sha256sum {} + | sort) | sha256sum > /root/before.sum'
check "re-running prepare keeps all files identical" "$PREP --template docs --domain docs.popug.cloud >/dev/null && cd /var/www/selfsteal && (find . -type f ! -name '.selfsteal-stamp*' -exec sha256sum {} + | sort) | sha256sum | cmp - /root/before.sum"
check "caddy reload works and site keeps answering" "caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && $(CV docs.popug.cloud 443) https://docs.popug.cloud/ | grep -q 'Popug Cloud documentation'"
check "unknown template is rejected" "! $PREP --template nope --domain a.b.example.com 2>&1 | grep -q Done; $PREP --template nope --domain a.b.example.com 2>&1 | grep -q 'unknown template'"

say ""; say "RESULT ($flavor, $(x 'caddy version | cut -d" " -f1')): $pass passed, $fail failed"
docker rm -f "$C" pebble-apt challtest-apt >/dev/null 2>&1 || true
[ "$fail" -eq 0 ]
