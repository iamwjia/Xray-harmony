// scripts/check-eol.js
//
// 统一行尾：仓库内文本文件必须是 LF。
//
// 为什么需要这条闸门（真实事故）：仓库配了 `core.autocrlf=true`，checkout 时把 LF 改写成 CRLF，
// 于是"同一个文件，有人提交 LF、有人提交 CRLF"，diff 里出现整文件变更、合并冲突莫名其妙。
// 现在用 `.gitattributes`（`* text=auto eol=lf`）+ 本闸门把它钉死。
//
// 只查 git 跟踪的文本文件；二进制按 .gitattributes 排除。

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const BIN_EXT = new Set(['.so', '.a', '.hap', '.hsp', '.zip', '.png', '.jpg', '.jpeg', '.webp', '.ico', '.ttf', '.otf', '.dat']);

let files = [];
try {
  files = execSync('git ls-files', { cwd: ROOT, encoding: 'utf8' }).split('\n');
} catch (e) {
  console.log('EOL SKIP: not a git repo or git unavailable');
  process.exit(0);
}

const crlf = [];
for (const rel of files) {
  const r = rel.trim();
  if (!r) continue;
  if (BIN_EXT.has(path.extname(r).toLowerCase())) continue;
  const p = path.join(ROOT, r);
  let raw;
  try {
    raw = fs.readFileSync(p);
  } catch (e) {
    continue;
  }
  if (raw.includes('\r\n') || raw.includes('\r')) {
    crlf.push(r);
  }
}

if (crlf.length === 0) {
  console.log(`EOL PASS: ${files.filter((f) => f.trim()).length} 个跟踪文件均为 LF`);
  process.exit(0);
}
console.log(`EOL FAIL: ${crlf.length} 个跟踪文件含 CRLF/CR`);
for (const f of crlf.slice(0, 30)) console.log('  ' + f);
if (crlf.length > 30) console.log(`  … 还有 ${crlf.length - 30} 个`);
console.log('\n修复：在仓库根执行 `git config core.autocrlf false`，再逐文件转 LF（或重新 checkout）。');
process.exit(1);
