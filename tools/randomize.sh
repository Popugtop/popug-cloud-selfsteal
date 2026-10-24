#!/usr/bin/env bash
# randomize.sh — give an unpacked template a per-installation variation.
#
#   randomize.sh --dir <template_dir> --seed <string> --domain <host> [--now <epoch>]
#
# <template_dir> holds  site/  and  Caddyfile.snippet.  The same seed always
# gives the same result, so re-running an install does not change the site.
#
# What changes:
#   * text tokens (see below) in every text file under <template_dir>
#   * files under site/assets/ are renamed to <hash>.<ext>; references are rewritten
#   * scoped-style ids (astro-cid-*) are replaced by per-node random ids
#   * file mtimes (so Last-Modified / ETag differ between installations)
#   * blocks wrapped in <!--@@S@@--> a <!--@@I@@--> b <!--@@E@@--> are reordered
#
# Tokens:  @@DOMAIN@@  @@BUILD_ID@@  @@VERSION@@  @@HOSTID@@  @@LASTMOD@@
#          @@PICK:a|b|c@@   @@AGO:1..3@@   @@BAR:<component>@@   @@UPTIME:<component>@@
# Must work with bash 3.2+, BSD/GNU userland and mawk/gawk/BWK awk.
set -Eeuo pipefail

dir="" seed="" domain="" now=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir="$2"; shift 2 ;;
    --seed) seed="$2"; shift 2 ;;
    --domain) domain="$2"; shift 2 ;;
    --now) now="$2"; shift 2 ;;
    *) echo "randomize: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -d "$dir" ] && [ -n "$seed" ] && [ -n "$domain" ] || { echo "usage: randomize.sh --dir D --seed S --domain H [--now EPOCH]" >&2; exit 2; }
[ -n "$now" ] || now=$(date +%s)

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
fmt_epoch() { date -u -d "@$1" +"$2" 2>/dev/null || date -u -r "$1" +"$2"; }

h=$(printf '%s' "$seed" | sha)
build_id=${h:0:8}
seednum=$((16#${h:8:7}))

# 90 dates (today first), "Mon D, YYYY"
dates=""
i=0
while [ "$i" -lt 90 ]; do
  d=$(fmt_epoch $((now - i * 86400)) "%b %-d, %Y" 2>/dev/null || fmt_epoch $((now - i * 86400)) "%b %d, %Y")
  dates="${dates}${d}|"
  i=$((i + 1))
done
dates=${dates%|}

# every file of the template except this script itself
list_files() { find "$dir" -type f ! -path "$dir/randomize.sh" | LC_ALL=C sort; }
is_text() { grep -Iq . "$1" 2>/dev/null; }

# shellcheck disable=SC2016  # the awk program must not be expanded by the shell
AWK_PROG='
function pick_hostid(   s, i, al) {
  al = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  s = ""
  for (i = 0; i < 64; i++) s = s substr(al, int(rand() * 64) + 1, 1)
  return s
}
function shuffle_blocks(s,   out, a, b, body, parts, n, i, j, t) {
  out = ""
  while ((a = index(s, "<!--@@S@@-->")) > 0) {
    b = index(s, "<!--@@E@@-->")
    if (b < a) break
    out = out substr(s, 1, a - 1)
    body = substr(s, a + 12, b - a - 12)
    n = split(body, parts, "<!--@@I@@-->")
    for (i = n; i > 1; i--) { j = int(rand() * i) + 1; t = parts[i]; parts[i] = parts[j]; parts[j] = t }
    for (i = 1; i <= n; i++) out = out parts[i]
    s = substr(s, b + 12)
  }
  return out s
}
function dstr(a) { return dates[a + 1] }
function bar(c,   a, st, out, cls, txt) {
  out = "<span class=\"bar\">"
  for (a = 89; a >= 0; a--) {
    st = state[c, a]
    if (st == "u") { cls = "u"; txt = "No downtime" }
    else if (st == "p") { cls = "p"; txt = "Partial outage" }
    else { cls = "m"; txt = "Major outage" }
    out = out "<i class=\"d " cls "\" title=\"" dstr(a) " - " txt "\"></i>"
  }
  return out "</span>"
}
function resolve(name, arg,   alts, n, k) {
  if (name == "DOMAIN") return domain
  if (name == "BUILD_ID") return build
  if (name == "VERSION") return version
  if (name == "HOSTID") return hostid
  if (name == "LASTMOD") { k = 3 + int(rand() * 40); return isodate(k) }
  if (name == "PICK") { n = split(arg, alts, "|"); return alts[int(rand() * n) + 1] }
  if (name == "AGO") return dstr(ago[arg + 0])
  if (name == "BAR") return bar(arg)
  if (name == "UPTIME") return uptime[arg]
  print "randomize: unknown token @@" name "@@" > "/dev/stderr"
  bad = 1
  return ""
}
function expand(s,   out, tok, p, name, arg) {
  out = ""
  while (match(s, /@@[A-Z0-9_]+(:[^@]*)?@@/)) {
    out = out substr(s, 1, RSTART - 1)
    tok = substr(s, RSTART + 2, RLENGTH - 4)
    s = substr(s, RSTART + RLENGTH)
    p = index(tok, ":")
    if (p) { name = substr(tok, 1, p - 1); arg = substr(tok, p + 1) } else { name = tok; arg = "" }
    out = out resolve(name, arg)
  }
  return out s
}
function isodate(k) { return isod[k] }
BEGIN {
  srand(seednum)
  version = (2 + int(rand() * 2)) "." (6 + int(rand() * 18)) "." int(rand() * 10)
  hostid = pick_hostid()
  split(datestr, dates, "|")
  split(isostr, isod_raw, "|")
  for (k = 0; k < 90; k++) isod[k] = isod_raw[k + 1]
  nc = split(comps, cl, ",")
  for (c = 1; c <= nc; c++) {
    np = 0; nm = 0
    for (a = 0; a < 90; a++) {
      r = rand(); st = "u"
      if (a > 0 && r < 0.004) st = "m"
      else if (a > 0 && r < 0.030) st = "p"
      state[cl[c], a] = st
    }
  }
  ago[1] = 7 + int(rand() * 14); ago[2] = 25 + int(rand() * 20); ago[3] = 52 + int(rand() * 30)
  state["cdn", ago[1]] = "p"; state["api", ago[2]] = "p"; state["storage", ago[3]] = "p"
  for (c = 1; c <= nc; c++) {
    np = 0; nm = 0
    for (a = 0; a < 90; a++) { if (state[cl[c], a] == "p") np++; if (state[cl[c], a] == "m") nm++ }
    u = 100 - np * 0.015 - nm * 0.08
    uptime[cl[c]] = sprintf("%.2f", u) "%"
  }
}
{ out = shuffle_blocks($0); out = expand(out); printf "%s", out }
END { if (bad) exit 3 }
'

iso=""
i=0
while [ "$i" -lt 90 ]; do
  iso="${iso}$(fmt_epoch $((now - i * 86400)) "%Y-%m-%d")|"
  i=$((i + 1))
done
iso=${iso%|}

# 1. tokens / shuffles
while IFS= read -r f; do
  is_text "$f" || continue
  grep -q '@@' "$f" || continue
  awk -v RS='\001' -v seednum="$seednum" -v domain="$domain" -v build="$build_id" \
      -v datestr="$dates" -v isostr="$iso" -v comps="storage,cdn,api,console,dns" \
      "$AWK_PROG" "$f" > "$f.rnd"
  cat "$f.rnd" > "$f"
  rm -f "$f.rnd"
done < <(list_files)

# 2. hashed asset names
site="$dir/site"
if [ -d "$site/assets" ]; then
  : > "$dir/.assetmap"
  while IFS= read -r f; do
    rel=${f#"$site/"}
    dn=$(dirname "$rel"); bn=$(basename "$rel")
    case "$bn" in *.*) ;; *) continue ;; esac
    ext=${bn##*.}
    hh=$(printf '%s' "$seed:$rel" | sha | cut -c1-10)
    new="$dn/$hh.$ext"
    mv "$f" "$site/$new"
    printf '%s %s\n' "$rel" "$new" >> "$dir/.assetmap"
  done < <(find "$site/assets" -type f | LC_ALL=C sort)
  esc() { printf '%s' "$1" | sed -e 's/[.[\*^$/|&]/\\&/g'; }
  sedscript="$dir/.assetmap.sed"; : > "$sedscript"
  while read -r old new; do
    printf 's|%s|%s|g\n' "$(esc "$old")" "$(esc "$new")" >> "$sedscript"
  done < "$dir/.assetmap"
  while IFS= read -r f; do
    is_text "$f" || continue
    sed -f "$sedscript" "$f" > "$f.rnd"
    cat "$f.rnd" > "$f"
    rm -f "$f.rnd"
  done < <(list_files | grep -v '/\.assetmap')
  rm -f "$dir/.assetmap" "$sedscript"
fi

# 2b. scoped-style ids
cids=$(list_files | xargs grep -hoE 'astro-cid-[a-z0-9]{8}' 2>/dev/null | LC_ALL=C sort -u || true)
if [ -n "$cids" ]; then
  sedscript="$dir/.cid.sed"; : > "$sedscript"
  for c in $cids; do
    printf 's|%s|c%s|g\n' "$c" "$(printf '%s' "$seed:$c" | sha | cut -c1-8)" >> "$sedscript"
  done
  while IFS= read -r f; do
    is_text "$f" || continue
    grep -q 'astro-cid-' "$f" || continue
    sed -f "$sedscript" "$f" > "$f.rnd"
    cat "$f.rnd" > "$f"
    rm -f "$f.rnd"
  done < <(list_files | grep -v '/\.cid\.sed')
  rm -f "$sedscript"
fi

# 3. modification times: one "deploy" moment per installation, small per-file jitter
if [ -d "$site" ]; then
  base=$((now - (20 + 16#${h:20:3} % 160) * 86400 - 16#${h:24:3} % 80000))
  n=0
  while IFS= read -r f; do
    ts=$((base + (n * 37 + 16#${h:30:2}) % 600))
    touch -t "$(fmt_epoch "$ts" "%Y%m%d%H%M.%S")" "$f"
    n=$((n + 1))
  done < <(find "$site" -type f | LC_ALL=C sort)
fi
