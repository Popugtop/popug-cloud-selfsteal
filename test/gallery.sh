#!/usr/bin/env bash
# Builds docs/gallery/index.html: screenshots (1440 and 390 px) of every page of every template
# plus the raw responses of the templates that have no HTML. Opens nothing by itself.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/docs/gallery"; rm -rf "$out"; mkdir -p "$out/img" "$out/txt"
export NOW; NOW=$(date +%s)
cd "$root"
# template|host|port|node examples
SITES="root|popug.cloud|9301|popug.cloud, www.popug.cloud
default|de1.popug.cloud|9302|any node without a specific role
cdn|se1.cdn.popug.cloud|9303|se1, se2, cz1, nl1, lv1, ee1, de1 (+ cdn.popug.cloud)
api|pl1.api.popug.cloud|9304|pl1, sg1 (+ api.popug.cloud)
storage|us1.s3.popug.cloud|9305|us1, tr1 (+ s3.popug.cloud)
registry|ru1.registry.popug.cloud|9306|ru1
docs|docs.popug.cloud|9307|docs.popug.cloud (root server)
status|status.popug.cloud|9308|status.popug.cloud (root server)
console|console.popug.cloud|9309|console.popug.cloud, auth.popug.cloud (root server)"
printf '%s\n' "$SITES" > "$out/sites.txt"
while IFS='|' read -r t host port _; do
  test/serve.sh "$t" "$host" "$port" >/dev/null
done < "$out/sites.txt"
asset() { find ".work/run/$1/site/assets" -type f -name "*.$2" | head -1 | sed "s|.work/run/$1/site||"; }
HERO=$(asset 9303 svg | grep img | head -1); HERO=$(find .work/run/9303/site/assets/img -name '*.svg' -size +400c | head -1 | sed 's|.work/run/9303/site||')
# template|label|port|host|path
PAGES="root|Landing page|9301|popug.cloud|/
root|404|9301|popug.cloud|/missing
default|Placeholder|9302|de1.popug.cloud|/
default|404|9302|de1.popug.cloud|/missing
cdn|Root (404 page)|9303|se1.cdn.popug.cloud|/
cdn|Asset: hero image|9303|se1.cdn.popug.cloud|$HERO
registry|Registry home|9306|ru1.registry.popug.cloud|/
registry|404|9306|ru1.registry.popug.cloud|/missing
docs|Overview|9307|docs.popug.cloud|/
docs|Quickstart|9307|docs.popug.cloud|/quickstart/
docs|Authentication|9307|docs.popug.cloud|/authentication/
docs|Storage|9307|docs.popug.cloud|/storage/
docs|CDN|9307|docs.popug.cloud|/cdn/
docs|API|9307|docs.popug.cloud|/api/
docs|CLI|9307|docs.popug.cloud|/cli/
docs|404|9307|docs.popug.cloud|/missing
status|Status|9308|status.popug.cloud|/
status|404|9308|status.popug.cloud|/missing
console|Sign in|9309|console.popug.cloud|/
console|Private beta|9309|console.popug.cloud|/beta/
console|404|9309|console.popug.cloud|/missing"
printf '%s\n' "$PAGES" > "$out/pages.txt"
for w in 1440 390; do
  args=(); i=0
  while IFS='|' read -r t label port host path; do
    i=$((i + 1)); args+=("$out/img/$i-$w.png" "https://$host:$port$path")
  done < "$out/pages.txt"
  node test/shoot.mjs "$w" "${args[@]}" >/dev/null
done
# raw responses for templates without HTML
resp() { # file host port method path
  { printf '$ curl -si%s https://%s%s\n' "$([ "$4" = GET ] || printf ' -X %s' "$4")" "$2" "$5"
    curl -sik -X "$4" --resolve "$2:$3:127.0.0.1" "https://$2:$3$5" | tr -d '\r' | head -c 900; printf '\n\n'; } >> "$1"
}
: > "$out/txt/api.txt"; : > "$out/txt/storage.txt"; : > "$out/txt/registry.txt"
for p in / /health /v1/buckets /nope /robots.txt; do resp "$out/txt/api.txt" pl1.api.popug.cloud 9304 GET "$p"; done
for p in / /my-bucket /my-bucket/image.jpg /Bad_Name; do resp "$out/txt/storage.txt" us1.s3.popug.cloud 9305 GET "$p"; done
resp "$out/txt/storage.txt" us1.s3.popug.cloud 9305 PUT /my-bucket/image.jpg
for p in /v2/ /v2/_catalog; do resp "$out/txt/registry.txt" ru1.registry.popug.cloud 9306 GET "$p"; done
docker ps -q --filter name=popug-tpl | xargs -r docker rm -f >/dev/null
python3 -I "$root/test/gallery.py" "$out"
echo "gallery: $out/index.html"
