const fs = require('fs');
const path = require('path');

const locales = ['hi', 'zh', 'ja', 'es', 'ml', 'ta', 'ru'];
const baseLang = 'en';

// Frozen documentation archives (see versions.json). They are snapshots of what
// a release actually shipped, already translated at cut time, so syncing English
// over them would overwrite historical content with today's docs.
const archivedSlugs = new Set(
  require('../versions.json').archived.map(v => v.slug)
);
const appDir = path.join(__dirname, '../app');
const baseDir = path.join(appDir, baseLang);

// Function to copy directory recursively
function copyDir(src, dest) {
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }

  const entries = fs.readdirSync(src, { withFileTypes: true });

  for (let entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    // Skip layout.tsx, global.css since they should be shared if possible,
    // actually in [lang], layout.tsx is usually at app/[lang]/layout.tsx
    // Nextra recommends layout to be in [lang], so let's copy everything.

    if (entry.isDirectory()) {
      if (archivedSlugs.has(entry.name)) {
        continue; // frozen archive — never re-synced
      }
      copyDir(srcPath, destPath);
    } else {
      // Only copy .mdx, _meta.js, _meta.json, and layout.tsx files
      if (entry.name.endsWith('.mdx') || entry.name === '_meta.js' || entry.name === '_meta.json' || entry.name === '_meta.ts' || entry.name === 'layout.tsx') {
        if (!fs.existsSync(destPath) || entry.name === 'layout.tsx') {
          console.log(`Copying ${srcPath} to ${destPath}`);
          if (entry.name === 'layout.tsx') {
            let content = fs.readFileSync(srcPath, 'utf8');
            content = content.replace(/getPageMap\('\/en'\)/g, `getPageMap('/${path.basename(dest)}')`);
            content = content.replace(/locale="en"/g, `locale="${path.basename(dest)}"`);
            fs.writeFileSync(destPath, content);
          } else if (entry.name.endsWith('.mdx')) {
            let content = fs.readFileSync(srcPath, 'utf8');
            // Rewrite absolute links to the correct locale
            content = content.replace(/href="\/en\//g, `href="/${path.basename(dest)}/`);
            content = content.replace(/\]\(\/en\//g, `](/${path.basename(dest)}/`);
            fs.writeFileSync(destPath, content);
          } else {
            fs.copyFileSync(srcPath, destPath);
          }
        }
      }
    }
  }
}

async function run() {
  console.log('Synchronizing i18n files...');
  
  if (!fs.existsSync(baseDir)) {
    console.error(`Base directory ${baseDir} does not exist! Please restructure app first.`);
    process.exit(1);
  }

  for (const locale of locales) {
    const localeDir = path.join(appDir, locale);
    console.log(`\nSyncing locale: ${locale}`);
    copyDir(baseDir, localeDir);
  }
  
  console.log('\nSync complete. (Note: Machine translation is not implemented in this local sync script yet. Use GitHub Actions for auto-translation.)');
}

run();
