// scripts/check-copy.js
//
// 文案闸门：指路文案必须对得上屏幕上的按钮。
//
// 为什么需要它：空态写「点下方『＋ 导入』」，按钮实际早就改成了「导入」，
// 用户会去找一个不存在的「＋」。这类"按钮改名、引用没跟"的问题编译不报、
// 截图不看空态也看不见，只能靠机器扫「」引用。
//
// 判定：页面 Text 里出现 `点下方「X」` / `点击下方「X」` 时，
//       X（去掉前导 ＋/+、去掉尾部 …）必须等于同文件里某个
//       Button('…') / textAction('…') / IconButton label 的字面量。
//
// 用法：node scripts/check-copy.js
//      node scripts/check-copy.js <目录>   —— 指定目录（用来自测闸门本身会不会抓错）

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const PAGES = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(ROOT, 'entry', 'src', 'main', 'ets', 'pages');

/** 收集一个文件里所有"能展示给用户的按钮文字" */
function collectLabels(src) {
  const labels = new Set();
  const push = (raw) => {
    const s = raw.trim();
    if (!s) return;
    labels.add(s);
    // 三元表达式形式的 label（如 '收起' : '导入'）会被拆成多个捕获组，逐个加
    labels.add(s.replace(/^'|'$/g, ''));
  };

  // Button('字面量')
  let re = /Button\(\s*'([^']+)'/g;
  let m;
  while ((m = re.exec(src)) !== null) push(m[1]);

  // textAction('字面量', ...)
  re = /\btextAction\(\s*'([^']+)'/g;
  while ((m = re.exec(src)) !== null) push(m[1]);

  // IconButton({ ... label: '字面量' ... }) 以及 label: cond ? 'A' : 'B'
  re = /\blabel\s*:\s*([^,\n}]+)/g;
  while ((m = re.exec(src)) !== null) {
    const expr = m[1];
    const litRe = /'([^']+)'/g;
    let lm;
    while ((lm = litRe.exec(expr)) !== null) push(lm[1]);
  }
  return labels;
}

/** 从"点下方「X」"里抽出 X 的候选名 */
function extractRefs(text) {
  const refs = [];
  const re = /点(?:击)?下方「([^」]+)」/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    // 去掉前导的 "＋ " / "+ "，与尾部省略号：按钮 label 上不会有这些
    const name = m[1].replace(/^[＋+]\s*/, '').replace(/…+$/, '').trim();
    if (name) refs.push({ name, raw: m[0] });
  }
  return refs;
}

const violations = [];
let checkedRefs = 0;

for (const file of fs.readdirSync(PAGES)) {
  if (!file.endsWith('.ets')) continue;
  const full = path.join(PAGES, file);
  const src = fs.readFileSync(full, 'utf8');
  const labels = collectLabels(src);

  // 只扫字面量文本（含跨行 + 拼接的近似：先按行取，再合并单引号片段）
  const lines = src.split('\n');
  lines.forEach((line, i) => {
    if (line.trim().startsWith('//') || line.trim().startsWith('*')) return;
    const refs = extractRefs(line);
    for (const r of refs) {
      checkedRefs++;
      if (!labels.has(r.name)) {
        violations.push({
          file: path.relative(ROOT, full),
          line: i + 1,
          name: r.name,
          raw: r.raw,
        });
      }
    }
  });
}

if (violations.length === 0) {
  console.log(`COPY PASS: ${checkedRefs} 处「点下方『X』」引用都能对上真实按钮`);
  process.exit(0);
}

console.log(`COPY FAIL: ${violations.length} 处指路文案指向了不存在的按钮`);
for (const v of violations) {
  console.log(`  ${v.file}:${v.line}  ${v.raw}  —— 本文件没有 label 为「${v.name}」的按钮`);
}
process.exit(1);
