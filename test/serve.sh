#!/usr/bin/env bash
# Dev helper: serve one template archive with Caddy in Docker, with randomization applied.
#   test/serve.sh <template> <domain> <host-port> [seed]
# Stops with:  docker rm -f popug-tpl-<port>
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
name="$1" domain="$2" port="$3" seed="${4:-$2}"
caddy_image="caddy:2.11.7"
run="$root/.work/run/$port"
rm -rf "$run"; mkdir -p "$run"
tar -xzf "$root/release/template-$name.tar.gz" -C "$run" --strip-components=1
docker run --rm -v "$run:/t" debian:12-slim bash /t/randomize.sh --dir /t --seed "$seed" --domain "$domain" --now "${NOW:-1780000000}"
cat > "$run/Caddyfile" <<CADDY
{
	auto_https disable_redirects
	admin off
	https_port 8443
	servers {
		protocols h1 h2
	}
}
https://$domain {
	tls internal
	import /t/Caddyfile.snippet
}
CADDY
docker rm -f "popug-tpl-$port" >/dev/null 2>&1 || true
docker run -d --name "popug-tpl-$port" -p "127.0.0.1:$port:8443" \
  -v "$run/site:/var/www/html:ro" -v "$run:/t:ro" "$caddy_image" caddy run --config /t/Caddyfile >/dev/null
for _ in $(seq 1 30); do
  curl -sk --resolve "$domain:$port:127.0.0.1" "https://$domain:$port/" -o /dev/null && exit 0
  sleep 0.5
done
docker logs "popug-tpl-$port" >&2; exit 1
