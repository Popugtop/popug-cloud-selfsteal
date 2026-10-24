<div align="center">

# 🦜 Popug Cloud · selfsteal

**A camouflage website for Reality “self-steal” nodes — installed in one command, configured in a terminal wizard.**

[![release](https://img.shields.io/github/v/release/Popugtop/popug-cloud-selfsteal?style=flat-square&color=e58f33&label=release)](https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest)
![Debian 12+ / Ubuntu 22.04+](https://img.shields.io/badge/Debian_12+_·_Ubuntu_22.04+-2a5745?style=flat-square)
![Caddy](https://img.shields.io/badge/Caddy-2.11-2a5745?style=flat-square)
![shellcheck](https://img.shields.io/badge/shellcheck-clean-2f9e5c?style=flat-square)

[Quick start](#-quick-start) · [The wizard](#-the-wizard) · [Templates](#-templates) · [Commands](#%EF%B8%8F-commands) · [Deployment guide](DEPLOY.md)

</div>

---

Every node gets its own domain (`se1.cdn.popug.cloud`, `pl1.api.popug.cloud`, …) with a real Let's Encrypt
certificate and a believable page behind it: a CDN edge, a JSON API, an S3 endpoint, a container registry.
Xray owns port 443 and hands every non-Reality connection to that site; a scanner or a browser sees an ordinary
service of a small cloud provider.

```
client ──443──▶ Xray (Reality) ──non-Reality traffic──▶ 127.0.0.1:8443  Caddy + template
```

The node itself (Remnanode / Xray, managed from the Remnawave panel) is **not** installed or modified —
this project only provides the site.

## 🚀 Quick start

1. **DNS.** Create an `A` record for the node, e.g. `se1.cdn.popug.cloud` → the node's IP
   (no `AAAA` record pointing elsewhere).
2. **Run** as root on the node:

   ```bash
   bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh)
   ```

3. Choose **Install**, answer the wizard, then put the printed values into the node's Reality profile in the panel:

   ```
   serverNames : ["se1.cdn.popug.cloud"]
   target/dest : "127.0.0.1:8443"
   xver        : 0
   ```

That's it. Later just type `selfsteal` on the node to get the same menu.

## 🧭 The wizard

```
  ┌  selfsteal 0.2.0  ·  install  · step 3/6
  │
  ◇  Domain     se1.cdn.popug.cloud
  ◇  DNS        ✓ 203.0.113.10 — this server
  │
  ◆  Template
  │  What a visitor or a scanner sees at https://se1.cdn.popug.cloud/
  │
  │    ○ api       JSON API gateway
  │  ❯ ● cdn       Edge asset host  ★ suggested
  │    ○ console   Console sign-in (invite-only notice)
  │    ○ default   Neutral placeholder for any host
  │    ○ docs      Documentation site
  │    ○ registry  Container registry endpoint
  │    ○ storage   S3-style object storage endpoint
  │
  └  ↑↓ move · enter select · ← back · ctrl+c quit
```

| Step | What happens |
|---|---|
| **Domain** | validated on enter; the hint shows this server's public IP for the A record |
| **DNS check** | *check now* or *skip*. The check runs right there; on a mismatch you see why and can **check again**, **change the domain** or **continue anyway** |
| **Template** | arrow keys; the one matching the name (`*.cdn.*` → `cdn`, `*.api.*` → `api`, `*.s3.*` → `storage`, …) is pre-selected |
| **Port** | loopback port for Xray's target, `8443` by default; a busy port is reported immediately |
| **E-mail** | optional, for Let's Encrypt expiry notices |
| **Options** | ufw rules · enable ufw · staging certificate · offer the node installer afterwards |
| **Review** | every value on one screen, any line can be changed — **nothing on the server is touched before *Install*** |

Keys: `↑↓` move · `enter` select · `space` toggle · `←` back · `ctrl+c` quit.

The main menu (`selfsteal` with no arguments) shows the current state and offers **Status, Re-configure,
Template, Domain, Logs, Restart, Certificate, Update, Uninstall, Prepare**. An error in one action returns to
the menu instead of closing it.

### Without the wizard

For scripts and mass roll-outs everything is still available as options:

```bash
bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh) @ install \
  --domain se1.cdn.popug.cloud --template cdn --yes
```

`--yes`, no terminal, or `SELFSTEAL_NO_TUI=1` → nothing is asked. In a terminal, options given on the command
line are pre-filled in the wizard; `install` with both `--domain` and `--template` skips it.

## 🎭 Templates

| Template | For | Typical hosts | Answers |
|---|---|---|---|
| `cdn` | nodes | `se1.cdn.popug.cloud` | branded 404 on `/`, static files under `/assets/` |
| `api` | nodes | `pl1.api.popug.cloud` | `{"service":"popug-api","status":"ok",…}`, JSON 401/404 |
| `storage` | nodes | `us1.s3.popug.cloud` | S3-style XML: `AccessDenied`, `NoSuchBucket`, `InvalidBucketName` |
| `registry` | nodes | `ru1.registry.popug.cloud` | short page, registry-style `401` on `/v2/` |
| `default` | nodes | anything else | neutral “you have reached a Popug Cloud endpoint” page |
| `root` | main server | `popug.cloud`, `www.popug.cloud` | landing page |
| `docs` | main server | `docs.popug.cloud` | documentation: overview, quickstart, auth, storage, CDN, API, CLI |
| `status` | main server | `status.popug.cloud` | status page with a 90-day history |
| `console` | main server | `console.popug.cloud`, `auth.popug.cloud` | sign-in page and a “private beta” notice, no working form |

Naming: `<country><n>.<role>.popug.cloud` — `cdn`: se1, se2, cz1, nl1, lv1, ee1, de1 · `api`: pl1, sg1 ·
`s3`: us1, tr1 · `registry`: ru1. Main-server pages are added to an existing Caddy with `prepare`
(see [DEPLOY.md §4](DEPLOY.md#4-the-main-domain-on-a-server-where-caddy-apt-already-runs)).

Everything is static: no backend, no external fonts / CDNs / analytics, no JavaScript, no forms that send data.

### Every node looks a little different

A seed (domain + machine-id) makes each installation unique but stable across re-installs:

- asset file names are hashed and references rewritten;
- `Last-Modified` / `ETag` differ;
- build id, API version, `HostId` in XML errors, dates and uptime history change;
- the order of some lists changes;
- no `Server` header anywhere (404s included), proper cache and security headers.

## ⌨️ Commands

```
selfsteal                     interactive menu
selfsteal install             install or re-apply (idempotent)
selfsteal update [--to TAG]   newer installer + templates; settings and certificates are kept
selfsteal status              state, container, listeners, certificate
selfsteal logs [-f] [--tail N]
selfsteal restart
selfsteal template [NAME]     switch the template (no NAME → picker)
selfsteal domain [NAME]       switch the domain (no NAME → wizard with DNS check)
selfsteal cert                discard and re-issue the certificate
selfsteal uninstall [--purge] remove the site (--purge also deletes certificates)
selfsteal templates           list templates
selfsteal prepare             only unpack a template for an EXISTING Caddy
```

<details>
<summary><b>All options</b></summary>

| Option | Meaning |
|---|---|
| `--domain NAME` | node host name (A/AAAA must point to this server) |
| `--template NAME` | template to serve |
| `--port N` | loopback port for Xray's target (default `8443`) |
| `--email ADDR` | contact e-mail for the certificate authority |
| `--staging` | Let's Encrypt staging CA for this run (tests) |
| `--skip-dns-check` | do not verify the DNS records |
| `--no-ufw` / `--enable-ufw` | do not touch the firewall / install and enable ufw |
| `--with-node` | afterwards offer to run the third-party `remnanode.sh` (downloaded and run as root, **not verified**) |
| `--seed STRING` | randomization seed |
| `--purge` | with `uninstall`: also delete certificates and volumes |
| `--out DIR`, `--mode public\|node` | for `prepare` |
| `-y`, `--yes` | never ask; fail if something required is missing |

Every option also works as `SELFSTEAL_<NAME>` (for example `SELFSTEAL_DOMAIN`).

</details>

## 📦 What gets installed

| | |
|---|---|
| Web server | official `caddy` image pinned by digest, Docker Compose, `network_mode: host` |
| Docker | from the official apt repository, only if missing |
| Files | `/opt/selfsteal/` — `docker-compose.yml`, `Caddyfile`, `snippet.caddy`, `site/`, `state.env` |
| Command | `/usr/local/bin/selfsteal` |
| Listens on | `127.0.0.1:8443` (TLS, for Xray) and `:80` (certificate challenge + redirect) |
| Certificate | Let's Encrypt, HTTP-01, exactly the node's domain (TLS-ALPN off — 443 belongs to Xray) |
| Firewall | ufw only: ssh (detected), 80, 443. Existing rules are never reset |

Requirements: Debian 12+ or Ubuntu 22.04+, root, free port 80, a domain pointing to the server.

## 🔄 Updating

On a node: `selfsteal update` (or **Update** in the menu) fetches the installer of the latest release and
re-applies the site; domain, template, port and certificates are kept. Pin a version with `--to 0.2.0`.
For servers using `prepare`, re-run it and reload Caddy. Details: [DEPLOY.md §5](DEPLOY.md#5-updating-templates-on-all-servers).

## 🔒 Integrity and safety

- Template archives come from the GitHub release of the **same version** as the installer and are checked against
  SHA256 values embedded in it; a mismatch aborts without touching the site.
- The installer's own checksum is in `SHA256SUMS` of every release.
- The Caddy image is pinned by digest.
- No secrets in URLs, arguments, logs or state files; Reality keys stay in the panel.

## 🛠 Development

```bash
npm install
node tools/build-release.mjs --repo Popugtop/popug-cloud-selfsteal   # → release/
test/gallery.sh                                   # screenshots of every page → docs/gallery/
test/e2e/run.sh                                   # full installer test: clean Debian 12 + Pebble (needs Docker)
test/e2e/existing-caddy.sh debian|cloudsmith      # `prepare` against an apt Caddy
```

The end-to-end tests issue real certificates from a local ACME server (Pebble) and never contact Let's Encrypt.
Shell scripts are kept clean under `shellcheck -S style`. Publishing a release: [DEPLOY.md §1](DEPLOY.md#1-publishing-a-release).

<details>
<summary><b>Repository layout</b></summary>

```
packages/design/   design tokens and shared components (Astro)
sites/root/        the popug.cloud landing page
templates/<name>/  one directory per template (+ caddy/Caddyfile.snippet, template.json)
installer/         selfsteal.sh (release data is embedded at build time)
tools/             build-release.mjs (archives, checksums, installer), randomize.sh
test/              serve.sh, curl-all.sh, shoot.mjs, gallery.sh, e2e/
```

</details>
