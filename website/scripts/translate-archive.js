#!/usr/bin/env node
/**
 * One-time translation of a frozen documentation archive.
 *
 *   node scripts/translate-archive.js v3.7
 *
 * ## Why this exists separately from translate.js
 *
 * Normally an archive never needs translating: `version-cut.js` snapshots every
 * locale tree as it existed at the tag, so the archive is born translated, and
 * `translate.js` deliberately skips archive directories so a frozen release is
 * never rewritten by a later machine-translation run.
 *
 * That breaks down for a release cut from a tag that predates the locale trees.
 * v3.7.6 is exactly that case: the site was English-only then, so the archive
 * has no `ja`, `zh`, `hi`, `es`, `ml`, `ta` or `ru` pages at all — and on a
 * static export a missing page is a 404, not a fallback.
 *
 * So this script does the "translate, then freeze" step retroactively: it fans
 * the archive's English pages out to the remaining locales and translates them
 * ONCE. After it runs, the archive is complete and `translate.js` continues to
 * ignore it forever.
 *
 * ## Cost
 *
 * This drives the same rate-limited free endpoints as translate.js, over the
 * full archived page set × 7 locales. Expect it to take a while. It is a
 * one-time operation per archive — do not wire it into a build.
 *
 * Re-running is safe: already-translated files are left alone unless --force.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const LOCALES = ['hi', 'zh', 'ja', 'es', 'ml', 'ta', 'ru'];
const WEBSITE_DIR = path.join(__dirname, '..');
const APP_DIR = path.join(WEBSITE_DIR, 'app');
const VERSIONS_FILE = path.join(WEBSITE_DIR, 'versions.json');

const slug = process.argv[2];
const force = process.argv.includes('--force');

if (!slug) {
  console.error('\n  usage: node scripts/translate-archive.js <slug> [--force]\n');
  process.exit(1);
}

const versions = JSON.parse(fs.readFileSync(VERSIONS_FILE, 'utf8'));
const archive = versions.archived.find(v => v.slug === slug);
if (!archive) {
  console.error(`\n  ✗ "${slug}" is not a registered archive (see versions.json)\n`);
  process.exit(1);
}

const enRoot = path.join(APP_DIR, 'en', slug);
if (!fs.existsSync(enRoot)) {
  console.error(`\n  ✗ app/en/${slug} does not exist — cut the archive first\n`);
  process.exit(1);
}

/** Every file under `dir`, relative to it. */
function walk(dir, base = dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, base, out);
    else out.push(path.relative(base, full));
  }
  return out;
}

const files = walk(enRoot);
const translatable = files.filter(
  f => f.endsWith('.mdx') || f.endsWith('_meta.js') || f.endsWith('notifications.json')
);

console.log(`\n  Filling archive "${slug}" (${archive.label}) into ${LOCALES.length} locales`);
console.log(`  ${translatable.length} translatable files per locale\n`);

const pending = [];

for (const locale of LOCALES) {
  const destRoot = path.join(APP_DIR, locale, slug);
  let copied = 0;

  for (const rel of files) {
    const src = path.join(enRoot, rel);
    const dest = path.join(destRoot, rel);
    if (fs.existsSync(dest) && !force) continue;

    fs.mkdirSync(path.dirname(dest), { recursive: true });

    if (rel === 'layout.tsx') {
      // Point the archive layout at this locale's page map, mirroring what
      // version-cut.js generates.
      let content = fs.readFileSync(src, 'utf8');
      content = content
        .replace(new RegExp(`getPageMap\\('/en/${slug}'\\)`, 'g'), `getPageMap('/${locale}/${slug}')`)
        .replace(/locale="en"/g, `locale="${locale}"`);
      fs.writeFileSync(dest, content);
    } else if (rel.endsWith('.mdx')) {
      // Rewrite absolute links so they stay inside this locale's archive.
      let content = fs.readFileSync(src, 'utf8');
      content = content
        .replace(/href="\/en\//g, `href="/${locale}/`)
        .replace(/\]\(\/en\//g, `](/${locale}/`);
      fs.writeFileSync(dest, content);
      if (translatable.includes(rel)) pending.push(dest);
    } else {
      fs.copyFileSync(src, dest);
      if (translatable.includes(rel)) pending.push(dest);
    }
    copied++;
  }
  console.log(`  · ${locale.padEnd(3)} ${copied} files staged`);
}

if (pending.length === 0) {
  console.log('\n  Nothing to translate — every locale is already filled.');
  console.log('  Re-run with --force to redo the translation.\n');
  process.exit(0);
}

console.log(`\n  Translating ${pending.length} files via scripts/translate.js …`);
console.log('  (rate-limited endpoints — this is slow, and runs once per archive)\n');

// translate.js skips archive paths by design, so hand it the files explicitly
// through the env escape hatch it honours for exactly this case.
try {
  execFileSync(
    process.execPath,
    [path.join(__dirname, 'translate.js'), ...pending],
    { cwd: WEBSITE_DIR, stdio: 'inherit', env: { ...process.env, TRACELET_ALLOW_ARCHIVED: '1' } }
  );
} catch (e) {
  console.error('\n  ✗ translation failed or was interrupted.');
  console.error('    Re-run this script to resume — completed files are skipped.\n');
  process.exit(1);
}

// The archive now has every locale; record it so the switcher stops falling
// back to English for this version.
archive.locales = ['en', ...LOCALES];
fs.writeFileSync(VERSIONS_FILE, JSON.stringify(versions, null, 2) + '\n');

console.log(`\n  ✓ archive "${slug}" now covers ${archive.locales.length} locales`);
console.log('  ✓ versions.json updated — the switcher will link locale-natively\n');
