import html, os, sys
out = sys.argv[1]
sites = [l.rstrip('\n').split('|') for l in open(f'{out}/sites.txt') if l.strip()]
pages = [l.rstrip('\n').split('|') for l in open(f'{out}/pages.txt') if l.strip()]
text = {n: open(f'{out}/txt/{n}.txt').read() for n in ('api', 'storage', 'registry')}
desc = {
 'root': 'Landing page of the main domain.',
 'default': 'Neutral placeholder for any host.',
 'cdn': 'Edge asset host: 404 on the root, static files under /assets/.',
 'api': 'JSON gateway: no HTML, only JSON responses.',
 'storage': 'S3-style endpoint: no HTML, only XML errors.',
 'registry': 'Container registry: a short page plus /v2/ protocol answers.',
 'docs': 'Documentation (root server).',
 'status': 'Service status page (root server).',
 'console': 'Console sign-in without a working form (root server).',
}
rows = []
idx = {}
for i, p in enumerate(pages, 1): idx.setdefault(p[0], []).append((i, p))
for t, host, port, nodes in sites:
    cards = []
    for i, (n, label, pt, h, path) in idx.get(t, []):
        shown = f'https://{h}{path}'
        cards.append(f'''<figure class="pg"><figcaption><b>{html.escape(label)}</b><code>{html.escape(shown)}</code></figcaption>
<div class="shots"><a class="d" href="img/{i}-1440.png" target="_blank"><img loading="lazy" src="img/{i}-1440.png" alt=""></a>
<a class="m" href="img/{i}-390.png" target="_blank"><img loading="lazy" src="img/{i}-390.png" alt=""></a></div></figure>''')
    if t in text:
        cards.append(f'<figure class="pg wide"><figcaption><b>Responses</b><code>curl -si</code></figcaption><pre>{html.escape(text[t])}</pre></figure>')
    rows.append(f'''<section id="{t}"><h2>{t} <small>{html.escape(desc[t])}</small></h2>
<p class="nodes">Used on: {html.escape(nodes)}</p><div class="grid">{''.join(cards)}</div></section>''')
nav = ''.join(f'<a href="#{t}">{t}</a>' for t, *_ in sites)
open(f'{out}/index.html', 'w').write(f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Template gallery</title>
<style>
:root{{--bg:#fcfbf8;--ink:#0f1613;--mut:#5b625c;--line:#e6e3da;--g:#2a5745}}
body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,sans-serif}}
header{{position:sticky;top:0;background:rgba(252,251,248,.95);backdrop-filter:blur(8px);border-bottom:1px solid var(--line);padding:12px 24px;z-index:5;display:flex;gap:16px;flex-wrap:wrap;align-items:center}}
header b{{margin-right:8px}} header a{{color:var(--g);text-decoration:none;font-weight:600}}
main{{max-width:1500px;margin:0 auto;padding:8px 24px 80px}}
section{{padding-top:36px}} h2{{font-size:26px;margin:0}} h2 small{{font-size:14px;color:var(--mut);font-weight:400;margin-left:10px}}
.nodes{{color:var(--mut);margin:4px 0 16px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(640px,1fr));gap:22px}}
.pg{{margin:0;border:1px solid var(--line);border-radius:12px;background:#fff;padding:14px;overflow:hidden}}
.pg.wide{{grid-column:1/-1}}
figcaption{{display:flex;justify-content:space-between;gap:12px;margin-bottom:10px;flex-wrap:wrap}} code{{color:var(--mut);font-size:12.5px}}
.shots{{display:flex;gap:14px;align-items:flex-start}}
.d{{flex:1;min-width:0;max-height:420px;overflow:hidden;border:1px solid var(--line);border-radius:6px;display:block}}
.m{{flex:0 0 150px;max-height:420px;overflow:hidden;border:1px solid var(--line);border-radius:6px;display:block}}
.shots img{{width:100%;display:block}}
pre{{margin:0;background:#1d2426;color:#e9efec;padding:14px 16px;border-radius:8px;overflow:auto;font-size:12.5px;line-height:1.55;max-height:520px}}
@media(max-width:700px){{.grid{{grid-template-columns:1fr}}}}
</style>
<header><b>Template gallery</b>{nav}</header>
<main><p style="color:var(--mut)">Desktop (1440 px) on the left, mobile (390 px) on the right. Click a screenshot to open it full size. Thumbnails show the top of long pages.</p>{''.join(rows)}</main></html>''')
