#!/usr/bin/env bash
# Serves every template (randomized) in Docker and records `curl -i` for typical requests into docs/curl/.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/docs/curl"; rm -rf "$out"; mkdir -p "$out"

req() { # file domain port method path [maxbytes]
  local f="$1" d="$2" p="$3" m="$4" path="$5" max="${6:-700}"
  { printf '$ curl -si%s https://%s%s\n' "$([ "$m" = GET ] || printf ' -X %s' "$m")" "$d" "$path"
    curl -sik -X "$m" --resolve "$d:$p:127.0.0.1" "https://$d:$p$path" | head -c "$max" | tr -d '\r'
    printf '\n\n'; } >> "$f"
}
asset_path() { find "$root/.work/run/$1/site/assets" -type f -name "*.$2" | head -1 | sed "s|$root/.work/run/$1/site||"; }

run() { # template domain port
  "$root/test/serve.sh" "$1" "$2" "$3" >/dev/null
}

run api pl1.api.popug.cloud 9101; f="$out/api.txt"; : > "$f"
for p in / /health /v1/buckets /nope /robots.txt; do req "$f" pl1.api.popug.cloud 9101 GET "$p"; done
req "$f" pl1.api.popug.cloud 9101 POST /v1/buckets

run storage us1.s3.popug.cloud 9102; f="$out/storage.txt"; : > "$f"
for p in / /my-bucket /my-bucket/image.jpg /Bad_Name /robots.txt; do req "$f" us1.s3.popug.cloud 9102 GET "$p"; done
req "$f" us1.s3.popug.cloud 9102 PUT /my-bucket/image.jpg

run registry ru1.registry.popug.cloud 9103; f="$out/registry.txt"; : > "$f"
for p in /v2/ /v2/_catalog /nope; do req "$f" ru1.registry.popug.cloud 9103 GET "$p"; done
req "$f" ru1.registry.popug.cloud 9103 GET / 500

run cdn se1.cdn.popug.cloud 9104; f="$out/cdn.txt"; : > "$f"
css=$(asset_path 9104 css); svg=$(asset_path 9104 svg)
for p in / "$css" "$svg" /robots.txt /favicon.svg /missing.js; do req "$f" se1.cdn.popug.cloud 9104 GET "$p" 560; done
run cdn se2.cdn.popug.cloud 9105

run docs docs.popug.cloud 9106; f="$out/docs.txt"; : > "$f"
for p in / /cli /cli/ /robots.txt /sitemap.xml /missing; do req "$f" docs.popug.cloud 9106 GET "$p" 520; done
req "$f" docs.popug.cloud 9106 GET "$(asset_path 9106 css)" 300

run status status.popug.cloud 9107; f="$out/status.txt"; : > "$f"
for p in / /missing; do req "$f" status.popug.cloud 9107 GET "$p" 520; done

run console console.popug.cloud 9108; f="$out/console.txt"; : > "$f"
for p in / /beta/ /missing /robots.txt; do req "$f" console.popug.cloud 9108 GET "$p" 480; done
echo "all templates served"
