#!/usr/bin/env node
/**
 * Freeze a released version of the docs into a browsable archive.
 *
 *   node scripts/version-cut.js <git-tag> <slug> [label]
 *   node scripts/version-cut.js v3.7.6 v3.7 3.7.6
 *
 * Copies `website/app/<locale>/**` at <git-tag> into `website/app/<slug>/<locale>/`
 * for every locale, then registers the archive in versions.json.
 *
 * ## Why the version segment comes first
 *
 * The obvious layout, `app/<locale>/<slug>/`, nests the archive inside the live
 * locale's `layout.tsx`. Next composes layouts, so the archive rendered its own
 * Nextra `<Layout>` *inside* the current one — two navbars, two logos, two
 * footers on every archived page. Hoisting the version to a top-level segment
 * makes each archive a sibling of the locale trees with its own layout, and
 * leaves the live docs structurally untouched.
 *
 * ## Why it reads from a git tag
 *
 * The archive must be what that release actually shipped, not today's docs with
 * an old label on them. Reading the working tree would produce a convincing lie.
 *
 * ## Why it snapshots every locale, not just English
 *
 * This is the whole reason archives cost nothing to maintain. `translate.js`
 * drives rate-limited free Google/Bing endpoints, so re-translating a frozen
 * archive on every run would be both slow and pointless. By copying the locale
 * trees as they already existed at the tag, an archive is born translated and is
 * never translated again. `i18n-sync.js` and `translate.js` skip archive
 * directories for the same reason.
 *
 * Corollary: cut a version only AFTER translations are current. Cutting early
 * freezes untranslated English into every locale, permanently.
 *
 * ## What is rewritten during the copy
 *
 * - `layout.tsx` is regenerated per locale so the archive gets its own sidebar
 *   (`getPageMap('/<locale>/<slug>')`) instead of inheriting the live one.
 * - `_meta.js` gains a hidden entry so the archive does not appear as a page
 *   inside its own navigation.
 * - Nothing else is touched. Content is copied byte-for-byte.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const LOCALES = ['en', 'hi', 'zh', 'ja', 'es', 'ml', 'ta', 'ru'];
const WEBSITE_DIR = path.join(__dirname, '..');
const APP_DIR = path.join(WEBSITE_DIR, 'app');
const REPO_ROOT = path.join(WEBSITE_DIR, '..');
const VERSIONS_FILE = path.join(WEBSITE_DIR, 'versions.json');

function git(args) {
  return execFileSync('git', args, { cwd: REPO_ROOT, maxBuffer: 1024 * 1024 * 64 });
}

function fail(message) {
  console.error(`\n  ✗ ${message}\n`);
  process.exit(1);
}

const [tag, slug, labelArg] = process.argv.slice(2);
if (!tag || !slug) {
  fail('usage: node scripts/version-cut.js <git-tag> <slug> [label]');
}
const label = labelArg || tag.replace(/^v/, '');

if (!/^[a-zA-Z0-9._-]+$/.test(slug)) {
  fail(`slug "${slug}" must be a safe path segment`);
}

// A slug that collides with a locale or an existing archive would shadow it.
if (fs.existsSync(path.join(APP_DIR, slug))) {
  fail(`app/${slug} already exists — pick another slug or delete it first`);
}
if (LOCALES.includes(slug)) {
  fail(`slug "${slug}" collides with a locale directory`);
}

try {
  git(['rev-parse', '--verify', `${tag}^{commit}`]);
} catch {
  fail(`git tag "${tag}" not found`);
}

console.log(`\n  Cutting docs archive "${slug}" from ${tag}\n`);

let totalFiles = 0;
const perLocale = [];
const capturedLocales = [];

for (const locale of LOCALES) {
  const prefix = `website/app/${locale}`;
  let listing;
  try {
    listing = git(['ls-tree', '-r', '--name-only', tag, `${prefix}/`]).toString();
  } catch {
    console.log(`  · ${locale.padEnd(3)} not present at ${tag} — skipped`);
    continue;
  }

  const files = listing.split('\n').filter(Boolean);
  if (files.length === 0) {
    console.log(`  · ${locale.padEnd(3)} not present at ${tag} — skipped`);
    continue;
  }

  const destRoot = path.join(APP_DIR, slug, locale);
  let count = 0;

  for (const file of files) {
    const rel = file.slice(prefix.length + 1);

    // Skip any archive that already existed at the tag: archives of archives
    // would nest without bound, and each is already reachable at its own URL.
    if (rel.split('/')[0].startsWith('v') && /^v\d/.test(rel.split('/')[0])) continue;

    // layout.tsx is regenerated below — the tag's copy points at the live
    // pageMap and would give the archive the current sidebar.
    if (rel === 'layout.tsx') continue;

    const dest = path.join(destRoot, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });

    let content = git(['show', `${tag}:${file}`]);

    // The archive lives exactly one directory deeper than the tree it came
    // from (app/<locale>/<slug>/… vs app/<locale>/…), so every relative import
    // that walks upward — `../../components/LottiePlayer` and friends — now
    // resolves one level short and fails the build. Add one hop to each.
    if (rel.endsWith('.mdx') || rel.endsWith('.tsx') || rel.endsWith('.ts') || rel.endsWith('.js')) {
      content = Buffer.from(
        content
          .toString('utf8')
          .replace(/(from\s*['"])(\.\.\/)/g, '$1../$2')
          .replace(/(import\s*['"])(\.\.\/)/g, '$1../$2')
          .replace(/(require\(\s*['"])(\.\.\/)/g, '$1../$2'),
        'utf8'
      );
    }

    fs.writeFileSync(dest, content);
    count++;
  }

  // The archive needs its own layout so Nextra builds the sidebar from the
  // archived page tree rather than inheriting the live one.
  fs.writeFileSync(
    path.join(destRoot, 'layout.tsx'),
    `import DocLayout from '../../../components/DocLayout'
import { getPageMap } from 'nextra/page-map'
import versions from '../../../versions.json'

// Frozen documentation archive — generated by scripts/version-cut.js from ${tag}.
// Do not edit by hand and do not translate: see versions.json for why.
export default async function ArchivedLayout({ children }: { children: React.ReactNode }) {
  const pageMap = await getPageMap('/${slug}/${locale}')
  const archive = versions.archived.find(v => v.slug === '${slug}')
  return (
    <DocLayout
      pageMap={pageMap}
      version={archive ? archive.label : '${label}'}
      locale="${locale}"
      archivedSlug="${slug}"
    >
      {children}
    </DocLayout>
  )
}
`
  );
  count++;

  capturedLocales.push(locale);
  perLocale.push(`${locale}:${count}`);
  totalFiles += count;
}

if (perLocale.length === 0) {
  fail(`no locale trees found under website/app/* at ${tag}`);
}

// No _meta.js patching is needed: the archive is a top-level segment, not a
// child of any locale, so it never appears in the live sidebar — and Nextra
// never has to validate a key pointing at a tree some locales do not have.

const versions = JSON.parse(fs.readFileSync(VERSIONS_FILE, 'utf8'));
if (!versions.archived.some(v => v.slug === slug)) {
  // Record the locales this archive actually contains. A release cut before a
  // locale existed simply has no pages in it, and on a static export a missing
  // page is a 404 — the switcher reads this to fall back to English instead.
  versions.archived.unshift({ label, slug, tag, locales: capturedLocales });
  fs.writeFileSync(VERSIONS_FILE, JSON.stringify(versions, null, 2) + '\n');
}

console.log(`  ✓ ${totalFiles} files across ${perLocale.length} locales (${perLocale.join(', ')})`);
console.log(`  ✓ registered "${label}" in versions.json`);
console.log(`  ✓ served at /${slug}/<locale>/ — outside the live locale trees\n`);
console.log(`  Archive is frozen: i18n-sync and translate skip "${slug}".`);
if (capturedLocales.length < LOCALES.length) {
  const missing = LOCALES.filter(l => !capturedLocales.includes(l));
  console.log(
    `\n  Note: ${missing.join(', ')} did not exist at ${tag}, so this archive is` +
    `\n  ${capturedLocales.join('/')}-only. To translate it once before freezing:` +
    `\n\n      node scripts/translate-archive.js ${slug}\n`
  );
} else {
  console.log('');
}
