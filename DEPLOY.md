# Deployment guide

Contents

1. [Publishing a release](#1-publishing-a-release)
2. [A new node (Docker, the default way)](#2-a-new-node-docker-the-default-way)
3. [A node that already has Caddy](#3-a-node-that-already-has-caddy)
4. [The main domain on a server where Caddy (apt) already runs](#4-the-main-domain-on-a-server-where-caddy-apt-already-runs)
5. [Updating templates on all servers](#5-updating-templates-on-all-servers)
6. [Everyday operations](#6-everyday-operations)
7. [Troubleshooting](#7-troubleshooting)

Short answers to common questions:

* **How is Caddy installed on a node?** In Docker. The installer installs Docker if it is missing and runs the
  official `caddy` image (pinned by digest) with Docker Compose in host-network mode. It does not use an apt Caddy.
* **Is "selfsteal" a separate program?** No. It is that same Caddy container serving a static site. Xray (Remnanode)
  stays separate and connects to the site on `127.0.0.1:8443`.
* **What if Caddy is already installed (apt or Docker)?** Use `selfsteal prepare` — see sections 3 and 4.

---

## 1. Publishing a release

Do this on your machine, not on a server. Node.js 22.23 or newer (Astro requirement; tested with 24) and `npm` are required.

```bash
npm install
node tools/build-release.mjs --repo Popugtop/popug-cloud-selfsteal
ls release/
# template-*.tar.gz (9 files), SHA256SUMS, selfsteal.sh
```

`release/selfsteal.sh` is the installer with the version, repository and the SHA256 of all nine archives
embedded. The archives are reproducible: building twice gives identical files.

Publish with the GitHub CLI (or upload the same files in the web UI):

```bash
git tag v0.2.2 && git push origin v0.2.2
gh release create v0.2.2 release/* --repo Popugtop/popug-cloud-selfsteal \
  --title "v0.2.2" --notes "Templates and installer v0.2.2"
```

Rules:

* Upload **every file from `release/`**: the installer downloads `template-<name>.tar.gz` and (for `update`)
  `selfsteal.sh` from `releases/download/v<version>/`.
* The tag must be `v<version>` where `<version>` is `version` in `package.json`.
* Never rebuild and replace files of a published tag: nodes pin the hashes of that exact build.
  Changed something? Bump the version, rebuild, publish a new tag.
* Sanity check after publishing, from any machine:
  `curl -sL https://github.com/Popugtop/popug-cloud-selfsteal/releases/download/v0.2.2/selfsteal.sh | sha256sum`
  must equal the `selfsteal.sh` line of `SHA256SUMS`.

Before the first `git push`, keep working files out of the repository. A suggested `.gitignore` already
excludes `node_modules`, `release`, `.work` and `*.tar.gz`; also add `docs/screens`, `docs/gallery`,
`docs/curl` and `design.tiff` (large, only needed locally).

---

## 2. A new node (Docker, the default way)

The node itself (Remnanode) is installed separately, through the panel or `remnanode.sh`. This guide adds
the camouflage site. Xray owns port 443; the site listens on `127.0.0.1:8443`.

### 2.1 Choose the name and create the DNS record

Name format: `<country><n>.<role>.popug.cloud`, for example `se1.cdn.popug.cloud` (`se2` for a second
node in the same country). Roles: `cdn`, `api`, `s3` (template `storage`), `registry`.

Create an `A` record pointing to the node's IPv4 address. **Do not leave an `AAAA` record that points
elsewhere**: the certificate authority prefers IPv6 and validation would fail. Check:

```bash
dig +short A    se1.cdn.popug.cloud
dig +short AAAA se1.cdn.popug.cloud     # empty, or the node's own IPv6
```

### 2.2 Check the server

```bash
ss -ltnp | grep -E ':(80|443|8443)\s'
```

* port **80** must be free (it is needed to obtain the certificate);
* port **443** is normally held by Xray — that is expected;
* port **8443** must be free (use `--port` to pick another loopback port).

If port 80 is taken by another web server, go to [section 3](#3-a-node-that-already-has-caddy).

### 2.3 Install

```bash
bash <(curl -Ls https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh) @ install
```

A wizard opens in the terminal (without `@ install` you get the main menu first). It asks for the domain,
offers to check the DNS records immediately and shows the result (fix the record and choose "Check again", or
skip), lets you pick the template with the arrow keys (the suggestion is derived from the name: `*.cdn.*` →
`cdn`, `*.api.*` → `api`, `*.s3.*` → `storage`, `*.registry.*` → `registry`, otherwise `default`), then the
port, an optional e-mail and the options (firewall, staging CA, node installer). The last screen shows
everything; any line can be changed there, and nothing on the server is touched before you choose **Install**.
Non-interactive:

```bash
bash <(curl -Ls …/selfsteal.sh) @ install --domain pl1.api.popug.cloud --template api --yes
```

What the installer does, in order: checks OS/root, installs missing helper packages, verifies that the
domain points to this server, installs Docker if needed, checks ports, downloads the template and **verifies
its SHA256**, randomizes it for this node, writes the Caddy configuration and validates it, starts the container,
waits for the certificate, adds ufw rules (only if ufw is installed), and installs the `selfsteal` command.

Firewall: if ufw is installed the installer adds ssh (detected), 80 and 443. If ufw is installed but
inactive it only adds the rules and tells you; enabling it is your decision (`ufw enable`) or use
`--enable-ufw` (installs and enables ufw — make sure ssh is allowed first). `--no-ufw` skips it.
The panel↔node port is handled by the node installation, not here.

### 2.4 Check the site

```bash
selfsteal status
curl -ksI --resolve se1.cdn.popug.cloud:8443:127.0.0.1 https://se1.cdn.popug.cloud:8443/
```

You should see a valid certificate (issuer Let's Encrypt), a normal HTTP answer for the template
(for `cdn`: a 404 page), and **no `Server:` header**.

### 2.5 Configure Xray in the panel

Use the values the installer printed:

| Field | Value |
|---|---|
| `target` (or `dest` in older cores) | `127.0.0.1:8443` |
| `xver` | `0` |
| `serverNames` | `["se1.cdn.popug.cloud"]` — the domain of **this** node |
| `privateKey`, `shortIds` | from your panel; the installer does not touch them |

Because every node has its own domain, `serverNames` must contain that node's domain, and the host/SNI
that clients use for the node must be the same domain. In practice that means a separate config profile (or
inbound) per node. Field names can differ slightly between panel versions; the semantics stay the same.

Apply the profile to the node and check from outside:

```bash
curl -sI https://se1.cdn.popug.cloud/      # served through 443 → Xray → site
```

The answer must be the template page, from the node's IP, with a valid certificate.

### 2.6 Moving from another self-steal setup

If the node already runs a different camouflage Caddy (for example one installed by another script, usually a
container such as `caddy-selfsteal` in `/opt/caddy`), stop it first so port 80 and the loopback port are free:

```bash
docker ps --format '{{.Names}}\t{{.Ports}}'        # find it
docker stop <name> && docker update --restart=no <name>
```

Then install with `--port <the port Xray already uses>` (for example `--port 9443`), so the Xray profile does not
need to change except for `xver` (`0`) if it was different. Old files can be removed after you verified the
new setup.

---

## 3. A node that already has Caddy

Two different situations.

**3.1 The existing Caddy is only an old camouflage site** — replace it, see [2.6](#26-moving-from-another-self-steal-setup).

**3.2 The existing Caddy serves something else and must stay.**
`selfsteal install` refuses to run when port 80 is busy. Use `prepare`: it downloads and verifies the template,
randomizes it, puts the site files in a directory and writes a ready Caddy block. It does **not** install Docker,
open ports or touch the firewall, and does not restart anything.

Constraint you cannot avoid: **Xray must own 443.** The existing Caddy therefore cannot serve other HTTPS sites
on 443 of this node. It may keep serving HTTP on port 80 and the camouflage site on a loopback port.

```bash
# 1. get the installer once (any version you published)
curl -fLo /tmp/selfsteal.sh https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh

# 2. unpack the template for this node in "node" mode
bash /tmp/selfsteal.sh @ prepare --out /var/www/selfsteal \
  --template cdn --domain se1.cdn.popug.cloud --mode node --port 8443
```

This creates `/var/www/selfsteal/site/se1.cdn.popug.cloud/` and `/var/www/selfsteal/se1.cdn.popug.cloud.caddy`.
The block binds to `127.0.0.1:8443`, requests the certificate by HTTP-01 (TLS-ALPN disabled), and contains the
template's own handlers (no `Server` header, custom 404, cache and security headers).

Then edit `/etc/caddy/Caddyfile` (keep a backup: `cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak`):

```caddyfile
{
	# redirects would point browsers to :8443, which is not reachable from outside
	auto_https disable_redirects
	# ...your existing global options stay here...
}

# ...your existing sites stay as they are...

import /var/www/selfsteal/*.caddy
```

If the Caddyfile already has a global options block at the top, add `auto_https disable_redirects` to it; do not create a second one.

```bash
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
curl -ksI --resolve se1.cdn.popug.cloud:8443:127.0.0.1 https://se1.cdn.popug.cloud:8443/
ss -ltn | grep 8443          # must show 127.0.0.1:8443 only
```

Then configure Xray exactly as in [2.5](#25-configure-xray-in-the-panel). Open ports 80 and 443 in your firewall
yourself (`prepare` does not touch it). The apt Caddy runs as user `caddy`; the files written by `prepare` are
world-readable, so no permission changes are needed.

Updating or removing:

* update: run `prepare` again with the new installer and `systemctl reload caddy`;
* remove: delete the `.caddy` file and the site directory, then reload Caddy.

This procedure was tested with Caddy 2.6.2 (the Debian 12 package) and 2.11.x (the official Caddy repository).

---

## 4. The main domain on a server where Caddy (apt) already runs

Goal: add `popug.cloud` and its sub-pages to the server that already hosts other sites (for example the
subscription page and a landing) **without touching those sites**. Everything is added with one extra line
in the Caddyfile.

| Template | Hosts |
|---|---|
| `root` | `popug.cloud`, `www.popug.cloud` |
| `docs` | `docs.popug.cloud` |
| `status` | `status.popug.cloud` |
| `console` | `console.popug.cloud`, `auth.popug.cloud` |
| `api` | `api.popug.cloud` |
| `cdn` | `cdn.popug.cloud` |
| `storage` | `s3.popug.cloud`, `storage.popug.cloud` |

### 4.1 DNS

Create `A` records (and `AAAA` only if the server really has IPv6) for **all** hosts in the table, pointing to
this server. Caddy obtains a separate certificate for each host automatically.

### 4.2 Install the pages

Ports 80/443 are already served by your Caddy; nothing needs to be opened or stopped.

```bash
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-$(date +%F)       # backup first
curl -fLo /tmp/selfsteal.sh https://github.com/Popugtop/popug-cloud-selfsteal/releases/latest/download/selfsteal.sh

OUT=/var/www/selfsteal
while IFS='|' read -r tpl hosts; do
  [ -n "$tpl" ] || continue            # tolerate blank lines from copy/paste
  bash /tmp/selfsteal.sh @ prepare --out "$OUT" --template "$tpl" --domain "$hosts" --yes
done <<'EOF'
root|popug.cloud,www.popug.cloud
docs|docs.popug.cloud
status|status.popug.cloud
console|console.popug.cloud,auth.popug.cloud
api|api.popug.cloud
cdn|cdn.popug.cloud
storage|s3.popug.cloud,storage.popug.cloud
EOF
ls "$OUT"            # *.caddy blocks and site/<host>/ directories
```

Each block is a normal Caddy site (`host1, host2 { … }`) with the template's headers and 404 pages.

### 4.3 Connect it to the existing Caddyfile

Add **one line** at the end of the file `/etc/caddy/Caddyfile` (outside any block); do not change your other sites.
This is a line of the Caddyfile, not a shell command. This appends it once:

```bash
grep -q 'import /var/www/selfsteal/\*.caddy' /etc/caddy/Caddyfile || echo 'import /var/www/selfsteal/*.caddy' >> /etc/caddy/Caddyfile
tail -n 3 /etc/caddy/Caddyfile
```

If one of these domains is already defined in the Caddyfile, Caddy reports a duplicate site address — remove or
rename the old definition first.

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

### 4.4 Verify

```bash
for h in popug.cloud www.popug.cloud docs.popug.cloud status.popug.cloud console.popug.cloud auth.popug.cloud api.popug.cloud cdn.popug.cloud s3.popug.cloud; do printf '%-24s %s\n' "$h" "$(curl -s -o /dev/null -w '%{http_code}' https://$h/)"; done
```

Expected: `200` for root, www, docs, status, console, auth and api; `404` for cdn; `403` for s3 (S3-style
`AccessDenied`). Certificates can take a few seconds to appear on the first request. Check that your existing sites
still answer. `journalctl -u caddy -n 50` shows certificate problems.

### 4.5 Notes

* **Updating:** publish a new release, re-run the loop (the `latest` URL picks up the new installer), `systemctl reload caddy`.
* **Status history:** the dates and bars of the status page are generated when `prepare` runs and are fixed
  afterwards. To refresh them, delete `/var/www/selfsteal/.selfsteal-stamp-status.popug.cloud` and re-run
  `prepare` for `status`, then reload.
* **Brand separation:** if this server also hosts another brand's sites, anyone can see that both share one IP address
  (reverse-IP lookups, certificate transparency logs). If the two must not be linkable, use a separate server or IP.
* **Removing a page:** delete its `.caddy` file and `site/<host>` directory, reload.

---

## 5. Updating templates on all servers

1. Change templates, bump `version` in `package.json`, rebuild and publish a new release (section 1).
2. **Docker nodes:** on each node run

   ```bash
   selfsteal update          # downloads the installer of the latest release and re-applies the site
   ```

   The domain, template, port and certificates are preserved. To pin a version: `selfsteal update --to 0.2.0`.
   Many nodes at once:

   ```bash
   for n in $(cat nodes.txt); do echo "== $n"; ssh root@"$n" 'selfsteal update --yes' ; done
   ```

3. **Nodes and servers using `prepare`:** repeat the `prepare` call(s) with the new installer and reload Caddy.

`update` makes the new site files live immediately; Caddy is restarted only if its configuration changed.

---

## 6. Everyday operations

| Task | Command |
|---|---|
| Menu with all of the below | `selfsteal` |
| State, container, listeners, certificate | `selfsteal status` |
| Logs | `selfsteal logs -f` (or `--tail 200`) |
| Restart Caddy | `selfsteal restart` |
| Change template | `selfsteal template api` |
| Change domain | `selfsteal domain de1.cdn.popug.cloud` (then update `serverNames` in the panel) |
| Re-issue the certificate | `selfsteal cert` |
| Remove (keeps certificates) | `selfsteal uninstall` |
| Remove everything | `selfsteal uninstall --purge` (firewall rules are left as they are) |

Files live in `/opt/selfsteal/`. Do not edit `Caddyfile` or `snippet.caddy` by hand: they are regenerated.

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `port 80 is already in use` | another web server holds it. Stop it, or use `prepare` ([section 3](#3-a-node-that-already-has-caddy)). |
| `… resolves to X which is not an address of this server` | the A record points elsewhere or has not propagated; fix it. NAT'd servers: the installer also compares with the public IP. `--skip-dns-check` overrides. |
| `has an AAAA record … not on this server` | remove the AAAA record or point it at this server. |
| `the site did not become ready in time` | the certificate was not issued. Check port 80 from outside, DNS, `selfsteal logs`. Re-running `install` retries immediately. Let's Encrypt limits repeated failures — test with `--staging` first. |
| `checksum mismatch` | the downloaded archive does not match the pinned hash: do not use it. Check that the release was not replaced after publishing. |
| `the generated Caddy configuration is invalid` | the message shows Caddy's error; usually a bad `--email`/URL value. |
| Xray cannot reach the site | `ss -ltn \| grep 8443` must show `127.0.0.1:8443`; the Xray container must use host networking to reach loopback. |
| `https://domain/` through 443 shows the wrong page | `serverNames`/SNI do not match the node's domain, or the profile is not applied to this node. |
| Docker installation fails | the installer uses the official Docker apt repository for Debian/Ubuntu; check internet access to `download.docker.com`. |

Privacy notes: node names appear in certificate transparency logs (no wildcard certificates are used), and the
node keeps the directory `/opt/selfsteal` and a container named `selfsteal-caddy` — these are visible only on the server.
