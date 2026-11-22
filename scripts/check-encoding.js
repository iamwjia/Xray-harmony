// scripts/check-encoding.js
//
// 目的：仓库里不允许出现"不是 UTF-8"的文本文件。
//
// 为什么需要这条闸门（真实事故）：往 `index.d.ts` 追加中文注释时用了 shell 的
// here-doc（`cat >> file <<'EOF'`），命令行按 GBK 写进去，文件从此不是合法 UTF-8：
// 编辑器里显示乱码、部分工具直接解析失败，而**编译不报错**——只有人眼才发现。
//
// 判定：
//   1. 文件必须能以 UTF-8 解码（BOM 允许，但会提示）；
//   2. 不含典型 mojibake 片段（UTF-8 被当 GBK 解出来的常见字）。
//
// 只查文本类扩展名；二进制目录（build/_toolchain/node_modules）跳过。
//
// 用法：node scripts/check-encoding.js

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const EXTS = new Set([
  '.ets', '.ts', '.js', '.cjs', '.mjs', '.cpp', '.cc', '.c', '.h', '.hpp',
  '.json', '.json5', '.md', '.ps1', '.sh', '.go', '.yaml', '.yml', '.txt', '.pro', '.cmake'
]);
const SKIP_DIRS = new Set(['.git', 'node_modules', 'oh_modules', '.hvigor', 'build', '_toolchain', '.idea', '.worktrees']);

// 典型 mojibake 特征：出现这些就说明"UTF-8 字节被当 GBK 解读后又存成 UTF-8"。
// 用码点而不是字面量：否则这个检查器会把自己判成脏文件。
const MOJIBAKE = [
  '\u951b', '\u9350', '\u9428', '\u93c4', '\u6d93\u7e2d', '\u951f\u65a4\u62f7',
  '\u5fd9\u8058', '\u8305\u8076', '\u8111\u964b', '\u9646\u8129'
];
const badUtf8 = [];
const mojibake = [];
const bom = [];

function walk(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (e) {
    return;
  }
  for (const ent of entries) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (SKIP_DIRS.has(ent.name)) continue;
      walk(full);
      continue;
    }
    if (!EXTS.has(path.extname(ent.name).toLowerCase())) continue;

    const buf = fs.readFileSync(full);
    const rel = path.relative(ROOT, full);

    if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) {
      bom.push(rel);
    }
    let text;
    try {
      text = new TextDecoder('utf-8', { fatal: true }).decode(buf);
    } catch (e) {
      badUtf8.push(rel);
      continue;
    }
    for (const m of MOJIBAKE) {
      if (text.includes(m)) {
        mojibake.push(`${rel}  (marker: ${m})`);
        break;
      }
    }
  }
}

walk(ROOT);

let failed = false;
if (badUtf8.length > 0) {
  failed = true;
  console.log(`ENCODING FAIL: ${badUtf8.length} 个文件不是合法 UTF-8`);
  for (const f of badUtf8) console.log('  ' + f);
}
if (mojibake.length > 0) {
  failed = true;
  console.log(`ENCODING FAIL: ${mojibake.length} 个文件含 mojibake`);
  for (const f of mojibake) console.log('  ' + f);
}
if (!failed) {
  console.log('ENCODING PASS: 全部文本文件均为合法 UTF-8，无 mojibake');
}
if (bom.length > 0) {
  // BOM 不算失败：Windows PowerShell 5.1 写 .ps1 需要 BOM 才能正确解析中文
  console.log(`note: ${bom.length} 个文件带 BOM（.ps1 带 BOM 是刻意的，其余可清理）`);
  for (const f of bom) console.log('  BOM ' + f);
}
process.exit(failed ? 1 : 0);
