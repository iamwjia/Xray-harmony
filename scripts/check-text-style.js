// scripts/check-text-style.js
//
// 文字层的两条硬闸之一：多行文本必须有行高。
//
// 为什么需要它：`fontSize(数字)=0` 只能证明"没有裸数字"，证明不了"用的是对的那一档"；
// 同理，字号错了顶多"偏小"，**行高缺失在中文里是整段挤在一起、无法扫读**。
// 许可页那 7 段正文就是"字号错 + 无行高"叠加，只查字号查不出来。
//
// 判定（按评审口径）：
//   未设 maxLines（ArkUI 默认可换行）或 maxLines > 1 的 Text  ⇒ 属性链内必须有 lineHeight(
// 排除：
//   - 单字符图标字形（'\u2713' / '\u2190' / '\u22ef' 等）
//   - 纯数字徽标（'1' / '2'）
//
// 实现注意：ArkTS 属性链是跨行写的，**不能用单行正则**。这里按括号配平找到 Text(...) 的结束，
// 再向后连续消费 .method(...) 直到链结束，在链内查 lineHeight。单行匹配会产生大量假阴性。
//
// 用法：node scripts/check-text-style.js [--verbose]

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DIRS = [
  path.join(ROOT, 'entry', 'src', 'main', 'ets', 'pages'),
  path.join(ROOT, 'entry', 'src', 'main', 'ets', 'components'),
];
const verbose = process.argv.includes('--verbose');

/** 从 i 处（指向 '(' ）开始，返回配平的右括号下标；找不到返回 -1 */
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

/** 从 i 处连续消费 `.name(...)` 调用链，返回链尾下标与链文本 */
function consumeChain(src, i) {
  let cur = i;
  const start = i;
  for (;;) {
    // 跳过空白
    let k = cur;
    while (k < src.length && /\s/.test(src[k])) k++;
    if (src[k] !== '.') break;
    // 读方法名
    let nameEnd = k + 1;
    while (nameEnd < src.length && /[A-Za-z0-9_$]/.test(src[nameEnd])) nameEnd++;
    let p = nameEnd;
    while (p < src.length && /\s/.test(src[p])) p++;
    if (src[p] !== '(') break;
    const close = matchParen(src, p);
    if (close < 0) break;
    cur = close + 1;
  }
  return { end: cur, text: src.slice(start, cur) };
}

const violations = [];
let scanned = 0;

for (const dir of DIRS) {
  if (!fs.existsSync(dir)) continue;
  for (const file of fs.readdirSync(dir)) {
    if (!file.endsWith('.ets')) continue;
    const full = path.join(dir, file);
    const src = fs.readFileSync(full, 'utf8');
    // 只找真正的 Text( 构造：前面不是标识符字符
    const re = /(^|[^A-Za-z0-9_$.])Text\s*\(/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      const openIdx = m.index + m[0].length - 1;
      const close = matchParen(src, openIdx);
      if (close < 0) continue;
      const args = src.slice(openIdx + 1, close);
      const chain = consumeChain(src, close + 1);
      scanned++;

      // 排除：单字符图标字形 / 纯数字徽标
      const argTrim = args.trim();
      const isGlyph = /^'\\u[0-9a-fA-F]{4}'$/.test(argTrim) ||
        /^'[^\x00-\x7F]'$/.test(argTrim) ||
        /^'[^\x00-\x7F]{1}'$/.test(argTrim);
      const isBadgeNumber = /^'\d{1,2}'$/.test(argTrim) ||
        /^`?\$\{[^}]*\}`?$/.test(argTrim) && chain.text.includes('borderRadius');
      if (isGlyph) continue;
      if (isBadgeNumber && chain.text.includes('borderRadius')) continue;

      const hasLineHeight = /\.lineHeight\s*\(/.test(chain.text);
      const maxLinesMatch = /\.maxLines\s*\(\s*(\d+)\s*\)/.exec(chain.text);
      const maxLines = maxLinesMatch ? parseInt(maxLinesMatch[1], 10) : null;
      const multiLine = maxLines === null || maxLines > 1;

      if (multiLine && !hasLineHeight) {
        const line = src.slice(0, openIdx).split('\n').length;
        violations.push({
          file: path.relative(ROOT, full),
          line,
          maxLines,
          snippet: argTrim.replace(/\s+/g, ' ').slice(0, 60),
        });
      }
    }
  }
}

if (verbose) {
  console.log(`scanned Text( occurrences: ${scanned}`);
}
if (violations.length === 0) {
  console.log('TEXT-STYLE PASS: 所有可换行 Text 都带了 lineHeight');
  process.exit(0);
}
console.log(`TEXT-STYLE FAIL: ${violations.length} 处可换行 Text 缺 lineHeight`);
for (const v of violations) {
  const ml = v.maxLines === null ? 'unset' : v.maxLines;
  console.log(`  ${v.file}:${v.line}  maxLines=${ml}  ${v.snippet}`);
}
process.exit(1);
