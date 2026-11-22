// scripts/check-text-style.js
//
// 文字层的三道硬闸：行高、字号下限、文案里的 markdown 残留。
//
// 为什么需要它：`fontSize(数字)=0` 只能证明"没有裸数字"，证明不了"用的是对的那一档"；
// 同理，字号错了顶多"偏小"，**行高缺失在中文里是整段挤在一起、无法扫读**。
// 许可页那 7 段正文就是"字号错 + 无行高"叠加，只查字号查不出来。
//
// 判定：
//   1) 未设 maxLines（ArkUI 默认可换行）或 maxLines > 1 的 Text ⇒ 属性链内必须有 lineHeight(
//   2) FontSize 里任何一档不得低于 MIN_FONT；页面里不得硬编码 .fontSize(数字)
//   3) Text() 的用户可见文案里不得出现 `**强调**`：ArkUI 的 Text 不解析 markdown，
//      写进去就是字面上两个星号（分流页、备份页、许可页真的漏到屏幕上了）
// 排除：
//   - 单字符图标字形（'\u2713' / '\u2190' / '\u22ef' 等）
//   - 纯数字徽标（'1' / '2'）
//   - 纯星号遮蔽串（'****-****-****'）
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
    // 跳过空白与注释：属性链中间可以写 `// 说明`，紧接着继续 `.foo(...)`。
    // 不跳注释的话，注释之后的 lineHeight 会被判成“没写”。
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

/** 强调标记：`**两个字以上**`。纯星号遮蔽串（'****-****'）不算 */
const EMPHASIS_RE = /\*\*[^*\s][^*\n]{0,20}[^*\s]\*\*/;

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

      const line = src.slice(0, openIdx).split('\n').length;

      // 3) markdown 强调残留（先判，图标字不可能命中）
      if (EMPHASIS_RE.test(args)) {
        violations.push({
          kind: 'md',
          file: path.relative(ROOT, full),
          line,
          snippet: argTrim.replace(/\s+/g, ' ').slice(0, 60),
        });
      }

      if (isGlyph) continue;
      if (isBadgeNumber && chain.text.includes('borderRadius')) continue;

      const hasLineHeight = /\.lineHeight\s*\(/.test(chain.text);
      const maxLinesMatch = /\.maxLines\s*\(\s*(\d+)\s*\)/.exec(chain.text);
      const maxLines = maxLinesMatch ? parseInt(maxLinesMatch[1], 10) : null;
      const multiLine = maxLines === null || maxLines > 1;

      if (multiLine && !hasLineHeight) {
        violations.push({
          kind: 'lineHeight',
          file: path.relative(ROOT, full),
          line,
          maxLines,
          snippet: argTrim.replace(/\s+/g, ' ').slice(0, 60),
        });
      }
    }
  }
}

// ---------- 字号下限与硬编码 ----------
// 用户反馈"有的字体过小"。真正的教训是：字号只靠 token 约束还不够，得有人守着下限，
// 否则下一次随手写 caption 12 就退回去了。
const MIN_FONT = 12;
const tokenFile = path.join(ROOT, 'entry', 'src', 'main', 'ets', 'common', 'Token.ets');
if (fs.existsSync(tokenFile)) {
  const t = fs.readFileSync(tokenFile, 'utf8');
  const re = /static\s+readonly\s+(\w+):\s*number\s*=\s*(\d+);/g;
  let m;
  while ((m = re.exec(t)) !== null) {
    const name = m[1];
    const val = Number(m[2]);
    // 行高类不在检查范围：LineHeight 里同名但含义不同，按块名粗筛
    if (t.slice(0, m.index).lastIndexOf('class FontSize') > t.slice(0, m.index).lastIndexOf('class LineHeight')) {
      if (val < MIN_FONT) {
        violations.push({ kind: 'fontToken', file: path.relative(ROOT, tokenFile), line: 0, snippet: `FontSize.${name} = ${val}` });
      }
    }
  }
}

// 页面里禁止硬编码字号（必须走 token，否则下限守不住）
for (const dir of DIRS) {
  if (!fs.existsSync(dir)) continue;
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith('.ets')) continue;
    const full = path.join(dir, name);
    const lines = fs.readFileSync(full, 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (/\.fontSize\(\s*\d+\s*\)/.test(line)) {
        violations.push({
          kind: 'fontHardcode',
          file: path.relative(ROOT, full),
          line: i + 1,
          snippet: '硬编码字号，应使用 FontSize token',
        });
      }
    });
  }
}

// ---------- 汇总 ----------
// 注意：这里必须累积完所有检查再退出。上一版在行高 PASS 时直接 process.exit(0)，
// 让后面追加的字号检查变成了永远执行不到的死代码——"已接入闸门"是假象。
if (verbose) {
  console.log(`scanned Text( occurrences: ${scanned}`);
}

const LABEL = {
  lineHeight: '可换行 Text 缺 lineHeight',
  md: 'Text 文案里有 markdown 强调（**）残留',
  fontToken: 'FontSize token 低于下限',
  fontHardcode: '硬编码字号',
};

if (violations.length === 0) {
  console.log(`TEXT-STYLE PASS: ${scanned} 处 Text 行高齐全 / 字号均 ≥ ${MIN_FONT} / 无 markdown 残留`);
  process.exit(0);
}

const byKind = {};
for (const v of violations) {
  (byKind[v.kind] = byKind[v.kind] || []).push(v);
}
console.log(`TEXT-STYLE FAIL: ${violations.length} 处`);
for (const kind of Object.keys(byKind)) {
  console.log(`  [${LABEL[kind] || kind}] ${byKind[kind].length} 处`);
  for (const v of byKind[kind]) {
    const extra = v.maxLines !== undefined ? `  maxLines=${v.maxLines === null ? 'unset' : v.maxLines}` : '';
    console.log(`    ${v.file}:${v.line}${extra}  ${v.snippet}`);
  }
}
process.exit(1);
