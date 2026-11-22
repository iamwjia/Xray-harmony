// scripts/fix-text-style.js
//
// 按 check-text-style.js 的判定，给"可换行但没行高"的 Text 补属性。
//
// 补什么，按语义分两类（不是见到就塞 lineHeight，也不是见到就塞 maxLines(1)）：
//   1) 短标签（字面量且可见字符 <= 12）：加 `.maxLines(1)`。
//      标签本来就不该折行，加 maxLines 比加行高更准，也不会改变现有视觉节奏。
//   2) 其余（正文、说明、动态拼接）：按链内已有 fontSize 对应的行高补 `.lineHeight(...)`。
//
// 用法：node scripts/fix-text-style.js [--dry]

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DIRS = [
  path.join(ROOT, 'entry', 'src', 'main', 'ets', 'pages'),
  path.join(ROOT, 'entry', 'src', 'main', 'ets', 'components'),
];
const dry = process.argv.includes('--dry');

const LINE_HEIGHT_BY_FONT = {
  'FontSize.display': 'LineHeight.display',
  'FontSize.titleLg': 'LineHeight.titleLg',
  'FontSize.titleMd': 'LineHeight.titleMd',
  'FontSize.bodyLg': 'LineHeight.bodyLg',
  'FontSize.body': 'LineHeight.body',
  'FontSize.bodySm': 'LineHeight.bodySm',
  'FontSize.caption': 'LineHeight.caption',
  'FontSize.fontChip': 'LineHeight.fontChip',
};

function matchParen(src, i) {
  let depth = 0;
  let inStr = false;
  let quote = '';
  for (let k = i; k < src.length; k++) {
    const ch = src[k];
    if (inStr) {
      if (ch === '\\') {
        k++;
        continue;
      }
      if (ch === quote) inStr = false;
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '`') {
      inStr = true;
      quote = ch;
      continue;
    }
    if (ch === '(') depth++;
    else if (ch === ')') {
      depth--;
      if (depth === 0) return k;
    }
  }
  return -1;
}

function consumeChain(src, i) {
  let cur = i;
  for (;;) {
    // 同 check-text-style.js：属性链中间可以有 `//` 注释，必须跳过
    let k = cur;
    for (;;) {
      while (k < src.length && /\s/.test(src[k])) k++;
      if (src[k] === '/' && src[k + 1] === '/') {
        while (k < src.length && src[k] !== '\n') k++;
        continue;
      }
      break;
    }
    if (src[k] !== '.') break;
    let nameEnd = k + 1;
    while (nameEnd < src.length && /[A-Za-z0-9_$]/.test(src[nameEnd])) nameEnd++;
    let p = nameEnd;
    while (p < src.length && /\s/.test(src[p])) p++;
    if (src[p] !== '(') break;
    const close = matchParen(src, p);
    if (close < 0) break;
    cur = close + 1;
  }
  return cur;
}

function visibleLen(literal) {
  const inner = literal.slice(1, -1);
  return inner.replace(/\\u[0-9a-fA-F]{4}/g, 'x').length;
}

let changed = 0;

for (const dir of DIRS) {
  if (!fs.existsSync(dir)) continue;
  for (const file of fs.readdirSync(dir)) {
    if (!file.endsWith('.ets')) continue;
    const full = path.join(dir, file);
    let src = fs.readFileSync(full, 'utf8');
    const edits = [];

    const re = /(^|[^A-Za-z0-9_$.])Text\s*\(/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      const openIdx = m.index + m[0].length - 1;
      const close = matchParen(src, openIdx);
      if (close < 0) continue;
      const args = src.slice(openIdx + 1, close);
      const chainEnd = consumeChain(src, close + 1);
      const chain = src.slice(close + 1, chainEnd);
      const argTrim = args.trim();

      const isGlyph = /^'\\u[0-9a-fA-F]{4}'$/.test(argTrim) || /^'[^\x00-\x7F]'$/.test(argTrim);
      if (isGlyph) continue;
      const isBadgeNumber = /^'\d{1,2}'$/.test(argTrim) && chain.includes('borderRadius');
      if (isBadgeNumber) continue;

      if (/\.lineHeight\s*\(/.test(chain)) continue;
      const maxLinesMatch = /\.maxLines\s*\(\s*(\d+)\s*\)/.exec(chain);
      const maxLines = maxLinesMatch ? parseInt(maxLinesMatch[1], 10) : null;
      if (maxLines !== null && maxLines <= 1) continue;

      const isShortLiteral = /^'[^']*'$/.test(argTrim) && visibleLen(argTrim) <= 12;
      let insert;
      if (isShortLiteral) {
        insert = '.maxLines(1)';
      } else {
        const fontMatch = /\.fontSize\(\s*(FontSize\.[A-Za-z]+)\s*\)/.exec(chain);
        const lh = fontMatch ? LINE_HEIGHT_BY_FONT[fontMatch[1]] : null;
        insert = `.lineHeight(${lh === null || lh === undefined ? 'LineHeight.bodySm' : lh})`;
      }
      edits.push({ at: chainEnd, text: insert, snippet: argTrim.slice(0, 40) });
    }

    if (edits.length === 0) continue;
    // 从后往前插，位置不互相影响
    edits.sort((a, b) => b.at - a.at);
    for (const e of edits) {
      src = src.slice(0, e.at) + e.text + src.slice(e.at);
      changed++;
      if (dry) console.log(`${path.basename(full)} + ${e.text}  <-  ${e.snippet}`);
    }
    if (!dry) fs.writeFileSync(full, src, 'utf8');
    console.log(`${path.basename(full)}: ${edits.length} \u5904`);
  }
}

console.log(dry ? `DRY RUN: ${changed} \u5904\u5f85\u4fee` : `FIXED: ${changed} \u5904`);
