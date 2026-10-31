// usage (from the package folder): node tailwind-lint.mjs <tailwind-css-entry>
// Project-wide version of Tailwind IntelliSense's canonical-class and conflict lints, over source files and CSS @apply.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const entry = process.argv[2];
if (!entry) {
  console.error('usage: node tailwind-lint.mjs <tailwind-css-entry>');
  process.exit(2);
}

const req = createRequire(path.resolve('package.json'));
let nodePath;
try {
  nodePath = req.resolve('@tailwindcss/node');
} catch {
  console.error(
    '@tailwindcss/node is not installed here; run from the package that uses Tailwind 4',
  );
  process.exit(2);
}
const { __unstable__loadDesignSystem } = await import(nodePath);
const { Scanner } = await import(createRequire(nodePath).resolve('@tailwindcss/oxide'));

const ds = await __unstable__loadDesignSystem(readFileSync(entry, 'utf8'), {
  base: path.dirname(path.resolve(entry)),
}).catch((/** @type {Error} */ e) => {
  console.error(`could not load ${entry}: ${e.message.split('\n')[0]}`);
  process.exit(2);
});
const scanner = new Scanner({});
const isClass = (c) => Boolean(ds.candidatesToCss([c])[0]);
const canonical = (c) => ds.canonicalizeCandidates?.([c], { rem: 16 })[0];
const propsOf = (c) =>
  [...ds.candidatesToCss([c])[0].matchAll(/^\s*([a-z-]+)\s*:/gm)]
    .map((m) => m[1])
    .sort()
    .join(',');

const files = execFileSync('git', ['ls-files', '-co', '--exclude-standard'], { encoding: 'utf8' })
  .split('\n')
  .filter((f) => /\.(tsx?|jsx?|mjs|html|vue|svelte|astro|mdx|css)$/.test(f));

const out = { canonical: [], conflicts: [] };
for (const file of files) {
  const content = readFileSync(file, 'utf8');
  if (/generated/i.test(content.slice(0, 300)) && /do not edit/i.test(content.slice(0, 300)))
    continue;
  const lineAt = (pos) => content.slice(0, pos).split('\n').length;
  const extension = path.extname(file).slice(1);

  for (const { candidate, position } of scanner.getCandidatesWithPositions({
    content,
    extension,
  })) {
    if (!isClass(candidate)) continue;
    const c = canonical(candidate);
    if (c && c !== candidate)
      out.canonical.push(`${file}:${lineAt(position)}  ${candidate} -> ${c}`);
  }

  for (const m of content.matchAll(/@apply\s+([^;]+);|(["'`])((?:(?!\2)[^\n$]){3,}?)\2/g)) {
    const tokens = (m[1] ?? m[3]).trim().split(/\s+/);
    const seen = new Map();
    for (const t of tokens) {
      if (!isClass(t)) continue;
      if (m[1]) {
        const c = canonical(t);
        if (c && c !== t) out.canonical.push(`${file}:${lineAt(m.index)}  ${t} -> ${c}`);
      }
      const key = `${t.includes(':') ? t.slice(0, t.lastIndexOf(':')) : ''}|${propsOf(t)}`;
      if (seen.has(key) && seen.get(key) !== t)
        out.conflicts.push(`${file}:${lineAt(m.index)}  ${seen.get(key)} <-> ${t}`);
      else seen.set(key, t);
    }
  }
}

console.log(`files scanned: ${files.length}`);
for (const [kind, lines] of Object.entries(out)) {
  const unique = [...new Set(lines)];
  console.log(`\n${kind} (${unique.length})`);
  for (const l of unique) console.log(l);
}
