/**
 * Automated i18n Translation Script (Parallel Multi-Engine Version)
 * 
 * Uses @vitalets/google-translate-api AND bing-translate-api concurrently.
 * Skips already translated files. Fails fast on rate limits.
 * 
 * ==========================================
 * AVAILABLE COMMANDS (HELP):
 * ==========================================
 * 
 * 1. Translate specific files:
 *    node scripts/translate.js app/en/page.mdx app/en/core/page.mdx
 * 
 * 2. Translate all files (Smart resume):
 *    node scripts/translate.js --all
 *    (This skips files that are already translated. If the script crashes halfway, just run this again to resume!)
 * 
 * 3. Force re-translate everything (Overwrite):
 *    node scripts/translate.js --all --force
 * 
 * 4. Sync English folders to other languages (Do this before translating new files):
 *    node scripts/i18n-sync.js
 * 
 * 5. Delete all translated languages (Clean up):
 *    node scripts/i18n-clean.js --all
 * 
 * 6. Master Command (Clean, Sync, and Translate from scratch):
 *    node scripts/i18n-run.js --all
 * ==========================================
 */

const fs = require('fs');
const path = require('path');
const { translate: googleTranslate } = require('@vitalets/google-translate-api');
const { translate: bingTranslate } = require('bing-translate-api');

const locales = ['hi', 'zh', 'ja', 'es', 'ml', 'ta', 'ru'];
const baseLang = 'en';

// Frozen documentation archives (see versions.json). These were snapshotted
// AFTER translation, so every locale copy is already translated and must never
// be translated again: re-running machine translation over them would rewrite
// historical content, and would multiply the cost of every --all run by the
// number of archived versions against rate-limited free endpoints.
const archivedSlugs = new Set(
  require('../versions.json').archived.map(v => v.slug)
);

const delay = (ms) => new Promise(res => setTimeout(res, ms));

async function translateLineGoogle(text, targetLang, retries = 5) {
  if (!text.trim()) return text;

  for (let i = 0; i < retries; i++) {
    try {
      // Much smaller delay (200ms) since the Chrome Dictionary endpoint handles huge concurrency!
      await delay(200 + (i * 1000));

      const url = `https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl=${targetLang}&q=${encodeURIComponent(text)}`;
      
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000);
      
      const response = await fetch(url, { signal: controller.signal });
      clearTimeout(timeoutId);

      if (!response.ok) {
        throw new Error(`Google API returned ${response.status}`);
      }

      const data = await response.json();
      // The response is an array of arrays, translated text is at data[0][0] or data.sentences[0].trans
      let translated = '';
      if (Array.isArray(data) && Array.isArray(data[0])) {
        translated = data[0][0];
      } else if (data.sentences && data.sentences[0]) {
        translated = data.sentences[0].trans;
      } else {
        translated = data; // fallback
      }

      // Fix spaces inside markdown bold tags (e.g. "** text **" -> "**text**")
      translated = translated.replace(/(\*\*)\s*(.*?)\s*(\*\*)/g, '$1$2$3');
      return translated;
    } catch (e) {
      const isRateLimit = e.message.includes('429') || e.message.includes('403') || e.name === 'TooManyRequestsError';

      if (isRateLimit && i < retries - 1) {
        const waitTime = 3000 * (i + 1); // 3s, 6s, 9s...
        console.log(`\n[GOOGLE API] Blocked (${e.message}). Waiting ${waitTime / 1000}s to retry...`);
        await delay(waitTime);
      } else {
        throw e; // Throw if it's a different error or we ran out of retries
      }
    }
  }
}

async function translateLineBing(text, targetLang) {
  if (!text.trim()) return text;

  // Bing uses different language codes for some languages (e.g., 'zh' -> 'zh-Hans')
  let bingLang = targetLang;
  if (targetLang === 'zh') bingLang = 'zh-Hans';

  await delay(100); // Bing handles more requests, minimal delay
  const res = await bingTranslate(text, null, bingLang);
  let translated = res.translation;
  // Fix spaces inside markdown bold tags (e.g. "** text **" -> "**text**")
  translated = translated.replace(/(\*\*)\s*(.*?)\s*(\*\*)/g, '$1$2$3');
  return translated;
}

async function translateTextWithProtection(text, targetLang, engine) {
  // Protect inline code with backticks
  const inlineCodes = [];
  let tempText = text.replace(/`([^`]+)`/g, (match) => {
    inlineCodes.push(match);
    return `NOTRANS${inlineCodes.length - 1}LATE`;
  });

  // Protect markdown URLs
  const mdUrls = [];
  tempText = tempText.replace(/\]\((.*?)\)/g, (match, url) => {
    mdUrls.push(url);
    return `](NOTRANSURL${mdUrls.length - 1})`;
  });

  let t = engine === 'google'
    ? await translateLineGoogle(tempText, targetLang)
    : await translateLineBing(tempText, targetLang);

  // Restore inline code
  inlineCodes.forEach((code, i) => {
    // Handle cases where the translator might have added spaces or changed case
    const regex = new RegExp(`NOTRANS\\s*${i}\\s*LATE`, 'gi');
    t = t.replace(regex, code);
  });

  // Restore markdown URLs
  mdUrls.forEach((url, i) => {
    // Note: Translator might have added a space before the parenthesis: "] (NOTRANSURL0)"
    // We can fix this by replacing "] (NOTRANSURL" with "](NOTRANSURL" before restoring, or just restore it normally.
    const regex = new RegExp(`\\]\\s*\\(\\s*NOTRANSURL\\s*${i}\\s*\\)`, 'gi');
    t = t.replace(regex, `](${url})`);
  });

  // Post-processing glossary overrides to fix contextual errors
  const glossary = {
    'ml': [
      { from: /സംസ്ഥാനം/g, to: 'അവസ്ഥ' }, // State (Province) -> State (Condition)
      { from: /സംസ്ഥാന/g, to: 'അവസ്ഥ' },
      { from: /തൂക്കിക്കൊല്ലുന്നതിനുപകരം/g, to: 'സ്റ്റക്ക് ആകുന്നതിന് പകരം' },
      { from: /തൂക്കിക്കൊല്ലുക/g, to: 'സ്റ്റക്ക് ആകുക' },
      { from: /തൂക്കിക്കൊല്ലുന്ന/g, to: 'സ്റ്റക്ക് ആകുന്ന' },
      { from: /തൂങ്ങിക്കിടക്കുന്നു/g, to: 'സ്റ്റക്ക് ആകുന്നു' }
    ],
    'hi': [
      { from: /राज्य/g, to: 'स्थिति' }
    ],
    'ta': [
      { from: /மாநிலம்/g, to: 'நிலை' },
      { from: /மாநில/g, to: 'நிலை' }
    ],
    'ja': [
      { from: /州/g, to: '状態' }
    ]
  };

  if (glossary[targetLang]) {
    glossary[targetLang].forEach(rule => {
      t = t.replace(rule.from, rule.to);
    });
  }

  return t;
}

async function translateMdx(content, targetLang, engine) {
  const lines = content.split('\n');
  const translatedLines = [];

  let inCodeBlock = false;
  let inFrontMatter = false;
  let isFirstLine = true;

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];

    if (isFirstLine && line.trim() === '---') {
      inFrontMatter = true;
      translatedLines.push(line);
      isFirstLine = false;
      continue;
    }
    if (inFrontMatter && line.trim() === '---') {
      inFrontMatter = false;
      translatedLines.push(line);
      continue;
    }
    if (inFrontMatter) {
      if (line.startsWith('title:')) {
        const titleMatch = line.match(/title:\s*"(.*)"/);
        if (titleMatch) {
          const t = engine === 'google'
            ? await translateLineGoogle(titleMatch[1], targetLang)
            : await translateLineBing(titleMatch[1], targetLang);
          translatedLines.push(`title: "${t}"`);
        } else {
          translatedLines.push(line);
        }
      } else {
        translatedLines.push(line);
      }
      continue;
    }

    isFirstLine = false;

    if (line.trim().startsWith('```')) {
      inCodeBlock = !inCodeBlock;
      translatedLines.push(line);
      continue;
    }
    if (inCodeBlock || line.startsWith('import ') || line.trim().startsWith('<') || line.trim() === '') {
      translatedLines.push(line);
      continue;
    }

    if (line.trim().startsWith('#')) {
      const hashes = line.match(/^#+/)[0];
      const text = line.replace(/^#+/, '').trim();
      const t = await translateTextWithProtection(text, targetLang, engine);
      translatedLines.push(`${hashes} ${t}`);
      continue;
    }

    if (line.trim().startsWith('- ') || line.trim().startsWith('* ')) {
      const match = line.match(/^[\s]*[\-*]\s+/);
      const prefix = match ? match[0] : '';
      const text = line.substring(prefix.length);
      const t = await translateTextWithProtection(text, targetLang, engine);
      translatedLines.push(`${prefix}${t}`);
      continue;
    }

    const t = await translateTextWithProtection(line, targetLang, engine);
    translatedLines.push(t);
  }

  return translatedLines.join('\n');
}

async function translateMetaJs(content, targetLang, engine) {
  const lines = content.split('\n');
  const translatedLines = [];

  for (let line of lines) {
    const match = line.match(/^(\s*(?:['"]?[\w-]+['"]?\s*:\s*)['"])(.*?)(['"],?\s*)$/);
    if (match) {
      const prefix = match[1];
      const text = match[2];
      const suffix = match[3];

      // Skip translating Nextra reserved keywords
      const keyMatch = prefix.match(/['"]?([\w-]+)['"]?\s*:/);
      if (keyMatch) {
        const key = keyMatch[1];
        if (['display', 'type', 'href', 'theme'].includes(key)) {
          translatedLines.push(line);
          continue;
        }
      }

      let t = engine === 'google'
        ? await translateLineGoogle(text, targetLang)
        : await translateLineBing(text, targetLang);

      // Escape double quotes returned by translator to prevent syntax errors
      t = t.replace(/"/g, '\\"');

      // Re-assemble the line
      // Notice: If the prefix ended with a single quote, we replace the prefix/suffix 
      // with double quotes to ensure the escaped \" works correctly.
      let newPrefix = prefix;
      let newSuffix = suffix;
      if (prefix.endsWith("'")) {
        newPrefix = prefix.slice(0, -1) + '"';
      }
      if (suffix.startsWith("'")) {
        newSuffix = '"' + suffix.slice(1);
      }
      
      translatedLines.push(`${newPrefix}${t}${newSuffix}`);
    } else {
      translatedLines.push(line);
    }
  }
  return translatedLines.join('\n');
}

async function translateJson(content, targetLang, engine) {
  const data = JSON.parse(content);
  
  // Translate badgeTitle
  if (data.badgeTitle) {
    data.badgeTitle = engine === 'google' 
      ? await translateLineGoogle(data.badgeTitle, targetLang)
      : await translateLineBing(data.badgeTitle, targetLang);
  }
  
  // Translate items
  if (data.items && Array.isArray(data.items)) {
    for (let item of data.items) {
      if (item.title) {
        item.title = engine === 'google'
          ? await translateLineGoogle(item.title, targetLang)
          : await translateLineBing(item.title, targetLang);
      }
      if (item.description) {
        item.description = engine === 'google'
          ? await translateLineGoogle(item.description, targetLang)
          : await translateLineBing(item.description, targetLang);
      }
    }
  }
  
  return JSON.stringify(data, null, 2);
}

function getAllFiles(dirPath, arrayOfFiles) {
  let files = fs.readdirSync(dirPath)
  arrayOfFiles = arrayOfFiles || []
  files.forEach(function (file) {
    if (fs.statSync(dirPath + "/" + file).isDirectory()) {
      if (archivedSlugs.has(file)) return; // frozen archive — never re-translated
      arrayOfFiles = getAllFiles(dirPath + "/" + file, arrayOfFiles)
    } else {
      arrayOfFiles.push(path.join(dirPath, "/", file))
    }
  })
  return arrayOfFiles
}

/**
 * True when `file` lives inside a frozen archive. Guards the explicit-file and
 * git-diff paths, which do not go through getAllFiles.
 */
function isArchivedPath(file) {
  // scripts/translate-archive.js performs the deliberate one-time fill of an
  // archive that predates the locale trees, and sets this to opt in.
  if (process.env.TRACELET_ALLOW_ARCHIVED === '1') return false;
  return path.resolve(file).split(path.sep).some(seg => archivedSlugs.has(seg));
}

async function run() {
  const args = process.argv.slice(2);
  let filesToTranslate = [];

  if (args.includes('--all')) {
    const baseDir = path.join(__dirname, '../app/en');
    const allFiles = getAllFiles(baseDir);
    filesToTranslate = allFiles.filter(f => 
      (f.endsWith('.mdx') || f.endsWith('_meta.js') || f.endsWith('notifications.json')) && 
      !f.includes('/privacy/') && 
      !f.includes('/terms/') &&
      !f.includes('/license/')
    );
  } else if (args.length > 0) {
    filesToTranslate = args.filter(f => !f.includes('/privacy/') && !f.includes('/terms/') && !f.includes('/license/') && !isArchivedPath(f));
  } else {
    try {
      const { execSync } = require('child_process');
      const diffOutput = execSync('git diff --name-only HEAD~1').toString();
      filesToTranslate = diffOutput.split('\n').filter(file => 
        file.includes(`app/${baseLang}/`) && 
        (file.endsWith('.mdx') || file.endsWith('notifications.json')) &&
        !file.includes('/privacy/') &&
        !file.includes('/terms/') &&
        !file.includes('/license/') &&
        !isArchivedPath(file)
      );
    } catch (e) {
      console.warn("Could not detect git changes. Please provide specific files or use --all.");
      process.exit(1);
    }
  }

  const force = args.includes('--force');

  // 1. Build Task Queue
  const queue = [];
  for (const file of filesToTranslate) {
    const absolutePath = path.resolve(file);
    if (!fs.existsSync(absolutePath)) continue;

    for (const locale of locales) {
      const destPath = absolutePath.replace(`/app/${baseLang}/`, `/app/${locale}/`);
      let shouldTranslate = force;

      if (!force) {
        if (!fs.existsSync(destPath)) {
          shouldTranslate = true;
        } else {
          const srcContent = fs.readFileSync(absolutePath, 'utf8');
          const destContent = fs.readFileSync(destPath, 'utf8');
          if (srcContent === destContent) {
            shouldTranslate = true;
          }
        }
      }

      // Skip if already translated, unless --force is used or it's a fallback
      if (shouldTranslate) {
        queue.push({
          srcPath: absolutePath,
          destPath: destPath,
          targetLocale: locale
        });
      }
    }
  }

  if (queue.length === 0) {
    console.log("All files are already translated! Nothing to do.");
    return;
  }

  console.log(`Starting parallel translation queue. ${queue.length} tasks remaining...`);

  // 2. Parallel Worker Logic
  async function worker(engine) {
    while (queue.length > 0) {
      const task = queue.shift();
      try {
        const relSrcPath = path.relative(path.join(__dirname, '../app/en'), task.srcPath);
        console.log(`[${engine.toUpperCase()}] Translating ${relSrcPath} to '${task.targetLocale}'...`);

        const content = fs.readFileSync(task.srcPath, 'utf8');
        let translated;
        if (task.srcPath.endsWith('.mdx')) {
          translated = await translateMdx(content, task.targetLocale, engine);
          // Fix internal links
          translated = translated.replace(/href="\/en\//g, `href="/${task.targetLocale}/`);
          translated = translated.replace(/\]\(\/en\//g, `](/${task.targetLocale}/`);
        } else if (task.srcPath.endsWith('_meta.js')) {
          translated = await translateMetaJs(content, task.targetLocale, engine);
        } else if (task.srcPath.endsWith('.json')) {
          translated = await translateJson(content, task.targetLocale, engine);
        }

        fs.mkdirSync(path.dirname(task.destPath), { recursive: true });
        fs.writeFileSync(task.destPath, translated, 'utf8');
        const relDestPath = path.relative(path.join(__dirname, '../app'), task.destPath);
        console.log(`[${engine.toUpperCase()}] ✓ Saved ${relDestPath}`);

      } catch (e) {
        console.error(`\n[FATAL ERROR] ${engine.toUpperCase()} blocked or failed: ${e.message}`);
        console.error("Stopping script immediately to prevent corrupted files.");
        process.exit(1); // Stop execution completely
      }
    }
  }

  // Run multiple Bing workers concurrently since Google is blocked locally
  await Promise.all([
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
    worker('google'),
  ]);

  console.log("\nAll translations completed successfully!");
  process.exit(0);
}

run().catch(e => {
  console.error("Global Error:", e);
  process.exit(1);
});
