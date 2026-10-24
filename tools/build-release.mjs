#!/usr/bin/env node
// Builds every template into release/template-<name>.tar.gz (deterministic)
// and writes release/SHA256SUMS. Archive layout:
//   template-<name>/{site/, Caddyfile.snippet, template.json, randomize.sh}
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'release');
const work = join(root, '.work', 'stage');
const MTIME = 1735689600; // fixed so archives are reproducible
const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;

const argv = process.argv.slice(2);
const repoIdx = argv.indexOf('--repo');
const repo = repoIdx >= 0 ? argv.splice(repoIdx, 2)[1] : process.env.GITHUB_REPOSITORY || '';
const only = argv;
const names = readdirSync(join(root, 'templates'), { withFileTypes: true })
  .filter((d) => d.isDirectory() && existsSync(join(root, 'templates', d.name, 'template.json')))
  .map((d) => d.name)
  .filter((n) => only.length === 0 || only.includes(n))
  .sort();

function walk(dir) {
  const res = [];
  for (const e of readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const p = join(dir, e.name);
    res.push(p);
    if (e.isDirectory()) res.push(...walk(p));
  }
  return res;
}

function octal(n, len) { return n.toString(8).padStart(len - 1, '0') + '\0'; }
function header(name, size, mode, type) {
  const h = Buffer.alloc(512);
  let prefix = '';
  let nm = name;
  if (Buffer.byteLength(nm) > 100) {
    const i = nm.lastIndexOf('/', 155);
    prefix = nm.slice(0, i); nm = nm.slice(i + 1);
  }
  h.write(nm, 0); h.write(octal(mode, 8), 100); h.write(octal(0, 8), 108); h.write(octal(0, 8), 116);
  h.write(octal(size, 12), 124); h.write(octal(MTIME, 12), 136); h.write('        ', 148);
  h.write(type, 156); h.write('ustar\0', 257); h.write('00', 263); h.write(prefix, 345);
  let sum = 0; for (const b of h) sum += b;
  h.write(octal(sum, 7).slice(0, 6) + '\0 ', 148);
  return h;
}
function tar(base, dirRoot) {
  const parts = [];
  for (const p of [dirRoot, ...walk(dirRoot)]) {
    const rel = join(base, relative(dirRoot, p)).replace(/\\/g, '/');
    const st = statSync(p);
    if (st.isDirectory()) { parts.push(header(rel + '/', 0, 0o755, '5')); continue; }
    const data = readFileSync(p);
    const mode = st.mode & 0o111 ? 0o755 : 0o644;
    parts.push(header(rel, data.length, mode, '0'), data, Buffer.alloc((512 - (data.length % 512)) % 512));
  }
  parts.push(Buffer.alloc(1024));
  return Buffer.concat(parts);
}

rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
const sums = [];
const info = {};
for (const name of names) {
  const src = join(root, 'templates', name);
  const stage = join(work, `template-${name}`);
  rmSync(stage, { recursive: true, force: true }); mkdirSync(stage, { recursive: true });
  const meta0 = JSON.parse(readFileSync(join(src, 'template.json'), 'utf8'));
  if (meta0.source) {
    const ws = JSON.parse(readFileSync(join(root, meta0.source, 'package.json'), 'utf8')).name;
    execFileSync('npm', ['run', 'build', '-w', ws], { cwd: root, stdio: 'ignore' });
    cpSync(join(root, meta0.source, 'dist'), join(stage, 'site'), { recursive: true });
  } else if (existsSync(join(src, 'astro.config.mjs'))) {
    execFileSync('npm', ['run', 'build', '-w', `@popug/tpl-${name}`], { cwd: root, stdio: 'ignore' });
    cpSync(join(src, 'dist'), join(stage, 'site'), { recursive: true });
  } else {
    cpSync(join(src, 'static'), join(stage, 'site'), { recursive: true });
  }
  cpSync(join(src, 'caddy', 'Caddyfile.snippet'), join(stage, 'Caddyfile.snippet'));
  const { source: _s, ...meta } = meta0;
  writeFileSync(join(stage, 'template.json'), JSON.stringify({ ...meta, version }, null, 2) + '\n');
  cpSync(join(root, 'tools', 'randomize.sh'), join(stage, 'randomize.sh'));
  const gz = gzipSync(tar(`template-${name}`, stage), { level: 9 });
  const file = `template-${name}.tar.gz`;
  writeFileSync(join(out, file), gz);
  const sha = createHash('sha256').update(gz).digest('hex');
  sums.push(`${sha}  ${file}`);
  info[name] = { sha, desc: meta.description };
  console.log(`${file}  ${gz.length} bytes  ${sha.slice(0, 12)}…`);
}
// installer with pinned data embedded
const inst = readFileSync(join(root, 'installer', 'selfsteal.sh'), 'utf8');
const block = [
  `VERSION="${version}"`,
  `REPO="${repo}"`,
  `TEMPLATE_NAMES="${names.join(' ')}"`,
  'template_desc() { case "$1" in',
  ...names.map((n) => `  ${n}) echo "${info[n].desc.replace(/"/g, '')}" ;;`),
  '  *) echo "" ;; esac; }',
  'template_sha256() { case "$1" in',
  ...names.map((n) => `  ${n}) echo "${info[n].sha}" ;;`),
  '  *) echo "" ;; esac; }',
].join('\n');
const embedded = inst.replace(/# @@EMBED:BEGIN@@\n[\s\S]*?# @@EMBED:END@@/, `# @@EMBED:BEGIN@@\n${block}\n# @@EMBED:END@@`);
if (embedded === inst) throw new Error('embed markers not found in installer');
const instPath = join(out, 'selfsteal.sh');
writeFileSync(instPath, embedded, { mode: 0o755 });
sums.push(`${createHash('sha256').update(embedded).digest('hex')}  selfsteal.sh`);
writeFileSync(join(out, 'SHA256SUMS'), sums.join('\n') + '\n');
console.log(`release ${version}: ${names.length} templates`);
