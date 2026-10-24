# Popug Cloud — site, templates and the selfsteal installer

This repository contains:

* **`popug.cloud`** — a small, static, fictional cloud platform site (storage, CDN, API);
* **9 templates** — pages and API-style responses used as the camouflage site of a Reality
  "self-steal" node and as the pages of the main domain;
* **`selfsteal.sh`** — an installer that puts one of the templates on a server behind Caddy.

The VPN node itself (Remnanode / Xray) is **not** part of this project and is never modified.
Xray listens on 443 and uses the site as its Reality `target`; this project only provides that site.

```
client ──443──▶ Xray (Reality) ──non-Reality traffic──▶ 127.0.0.1:8443  Caddy + template
```

## Quick start (a node)

DNS first: create an `A` record for the node, for example `se1.cdn.popug.cloud` → the node's IP.
Then, as root on the node:

```bash
bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/download/v0.1.1/selfsteal.sh) @ install
```

The installer asks for the domain and the template (it suggests one from the name) and prints the
values for the panel at the end. Non-interactive form:

```bash
bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/download/v0.1.1/selfsteal.sh) @ install \
  --domain se1.cdn.popug.cloud --template cdn --yes
```

Step-by-step guides (new node, node with an existing Caddy, main domain on a server with Caddy,
updates, troubleshooting): see [DEPLOY.md](DEPLOY.md).

## What gets installed

| Item | Value |
|---|---|
| Web server | official `caddy` image (version pinned by digest), run with Docker Compose, `network_mode: host` |
| Docker | installed from the official apt repository if it is missing |
| Directory | `/opt/selfsteal/` (`docker-compose.yml`, `Caddyfile`, `snippet.caddy`, `site/`, `state.env`) |
| Command | `/usr/local/bin/selfsteal` |
| Listens on | `127.0.0.1:8443` (TLS, for Xray) and `:80` (certificate challenge + redirect to https) |
| Certificate | Let's Encrypt, HTTP-01, for exactly the node's domain (TLS-ALPN is disabled — 443 belongs to Xray) |
| Firewall | ufw only: allows ssh (detected from sshd), 80 and 443. Existing rules are never reset. |

Requirements: Debian 12+ or Ubuntu 22.04+, root, free port 80, a domain whose A/AAAA records point
to the server. Port 443 is expected to be used by Xray.

## Templates

| Template | Typical hosts | Answers |
|---|---|---|
| `cdn` | `se1.cdn.popug.cloud`, `cdn.popug.cloud` | branded 404 on `/`, static files under `/assets/` |
| `api` | `pl1.api.popug.cloud`, `api.popug.cloud` | `{"service":"popug-api","status":"ok","version":"…"}` on `/`, JSON 401/404 |
| `storage` | `us1.s3.popug.cloud`, `s3.popug.cloud` | S3-style XML: `AccessDenied`, `NoSuchBucket`, `InvalidBucketName` |
| `registry` | `ru1.registry.popug.cloud` | short page, registry-style `401` on `/v2/` |
| `default` | any node without a specific role | neutral "you have reached a Popug Cloud endpoint" page |
| `root` | `popug.cloud`, `www.popug.cloud` | landing page |
| `docs` | `docs.popug.cloud` | documentation (overview, quickstart, auth, storage, CDN, API, CLI) |
| `status` | `status.popug.cloud` | status page with a 90-day history |
| `console` | `console.popug.cloud`, `auth.popug.cloud` | sign-in page and a "private beta" page, no working form |

Host names follow `<country><n>.<role>.popug.cloud`. Role layout used here:
`cdn` — se1, se2, cz1, nl1, lv1, ee1, de1; `api` — pl1, sg1; `storage` (`*.s3`) — us1, tr1; `registry` — ru1.
`docs`, `status` and `console` are single pages for the main server, not for nodes.

Everything is static: no backend, no external fonts/CDNs/analytics, no JavaScript, no forms that send data.

## Commands

```
selfsteal install            install or re-apply (idempotent)
selfsteal update [--to TAG]  fetch a newer installer release and re-apply
selfsteal uninstall [--purge]
selfsteal status | logs [-f] [--tail N] | restart
selfsteal template [NAME]    switch template without reinstalling
selfsteal domain [NAME]      switch domain
selfsteal cert               discard and re-issue the certificate
selfsteal templates          list templates
selfsteal prepare            only unpack a template for an EXISTING Caddy (see DEPLOY.md)
```

Options: `--domain`, `--template`, `--port` (default 8443), `--email`, `--staging`
(Let's Encrypt staging), `--skip-dns-check`, `--no-ufw`, `--enable-ufw`, `--with-node`, `--seed`,
`--purge`, `--out`/`--mode` (prepare), `-y/--yes`, `-h/--help`. Every option also works as
`SELFSTEAL_<NAME>` (for example `SELFSTEAL_DOMAIN`).

`--with-node` (off by default) offers to run the third-party `remnanode.sh` afterwards. That script is
downloaded and executed as root and is **not** verified by this installer.

## Values for the panel

At the end of `install` the installer prints them. For a node `se1.cdn.popug.cloud`:

```
serverNames : ["se1.cdn.popug.cloud"]
target/dest : "127.0.0.1:8443"
xver        : 0
```

and an `realitySettings` fragment with placeholders for the key pair and short ids (they come from the panel;
the installer never generates or stores them).

## Per-node randomization

Every installation is slightly different, derived from a seed (domain + machine-id), so the same
node always gets the same result and different nodes do not serve identical bytes:

* asset file names are replaced with hashes, references rewritten;
* `Last-Modified` / `ETag` values differ;
* build id, API version, `HostId` in XML errors, dates and uptime in the status history change;
* the order of some lists changes;
* Caddy sends no `Server` header (also on 404s), with proper cache and security headers.

## Integrity and safety

* Template archives are downloaded from the GitHub release of the **same version** as the installer
  and verified against SHA256 values embedded in the installer. A mismatch aborts without touching the site.
* The installer itself is fetched over HTTPS from GitHub; its own checksum is listed in `SHA256SUMS`
  of the release if you want to check it by hand.
* No secrets are passed in URLs or arguments and none are written to logs or state files.
* The Caddy image is pinned by digest.

## Repository layout

```
packages/design/   design tokens and shared components (Astro)
sites/root/        the popug.cloud landing page
templates/<name>/  one directory per template (+ caddy/Caddyfile.snippet, template.json)
installer/         selfsteal.sh (release data is embedded at build time)
tools/             build-release.mjs (archives, checksums, installer), randomize.sh
test/              serve.sh, curl-all.sh, shoot.mjs, gallery.sh, e2e/ (Debian 12 + Pebble)
```

## Development

```bash
npm install
node tools/build-release.mjs --repo Popugtop/popug-cloud-selfsteal   # writes release/
test/gallery.sh                 # screenshots of every page → docs/gallery/index.html
test/e2e/run.sh                 # full installer test in a clean Debian 12 (needs Docker)
test/e2e/existing-caddy.sh debian|cloudsmith   # `prepare` against a Caddy installed with apt
```

The end-to-end tests issue real certificates from a local ACME test server (Pebble); they never
contact Let's Encrypt or any of your servers. Shell scripts are kept clean under `shellcheck -S style`.
