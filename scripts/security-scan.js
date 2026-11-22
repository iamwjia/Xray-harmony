#!/usr/bin/env node
/**
 * scripts/security-scan.js — 项目内自研静态安全扫描
 *
 * 为什么不直接上现成工具：
 *   - semgrep / CodeQL 对 ArkTS（.ets）没有官方规则集，直接跑会把整片文件当"无法解析"跳过；
 *   - gitleaks 能扫密钥，但不认识本项目"凭据存 SecretStore、日志统一走 Logger.redact"的设计约束；
 *   - 真正高频、且本项目会踩的坑只有那几类，用 grep + 白名单能查得更准。
 * 外部工具建议见 doc/security-audit.md（保留给"通用 CVE / 依赖漏洞"这类自研查不了的部分）。
 *
 * 用法：node scripts/security-scan.js [--strict]
 *   --strict 时把 WARN 也算失败（默认只 FAIL 才退出非零）
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const STRICT = process.argv.includes('--strict');

const findings = [];
function add(level, rule, file, line, msg) {
  findings.push({ level, rule, file: path.relative(ROOT, file).replace(/\\/g, '/'), line, msg });
}

function walk(dir, out) {
  if (!fs.existsSync(dir)) {
    return;
  }
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const st = fs.statSync(full);
    if (st.isDirectory()) {
      if (['build', 'node_modules', '.git', 'oh_modules', '_archive-2026-11-22'].includes(name)) {
        continue;
      }
      walk(full, out);
    } else {
      out.push(full);
    }
  }
}

const etsDir = path.join(ROOT, 'entry/src/main/ets');
const cppDir = path.join(ROOT, 'entry/src/main/cpp');
const scriptsDir = path.join(ROOT, 'scripts');
const testsDir = path.join(ROOT, 'tests');

const etsFiles = [];
walk(etsDir, etsFiles);
const codeFiles = etsFiles.filter((f) => f.endsWith('.ets'));
const nativeFiles = [];
walk(cppDir, nativeFiles);

// ---------- 规则 1：硬编码凭据 ----------
// 排除测试/占位值（全 0 UUID、example.com、demo 等）
const SECRET_PATTERNS = [
  { re: /(?<![\w-])(?:password|passwd|pwd|secret|token|apikey|api_key)\s*[:=]\s*['"][^'"]{6,}['"]/i, msg: '硬编码口令/令牌字面量' },
  { re: /id\s*:\s*['"][0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}['"]/i, msg: '硬编码 UUID' },
  { re: /private\s*-?\s*key\s*[:=]/i, msg: '疑似私钥字面量' },
];
const ALLOW_HINTS = ['00000000-0000-0000-0000-000000000000', 'example.com', 'demo', 'placeholder', 'hint'];

for (const f of codeFiles.concat(nativeFiles.filter((x) => /\.(cpp|h)$/.test(x)))) {
  const text = fs.readFileSync(f, 'utf8');
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    const lower = line.toLowerCase();
    if (ALLOW_HINTS.some((h) => lower.includes(h))) {
      return;
    }
    for (const p of SECRET_PATTERNS) {
      if (p.re.test(line)) {
        add('FAIL', 'hardcoded-secret', f, i + 1, p.msg + '：' + line.trim().slice(0, 80));
      }
    }
  });
}

// ---------- 规则 2：明文 HTTP 端点 ----------
// 只看"真的当端点用"的写法；startsWith/endsWith/replace/includes 这类是在判断或规范化
// 协议前缀（订阅地址校验、去协议取 host），不是明文请求端点——第一版把它们全报成 FAIL，
// 属于规则太糙：安全扫描本身误报率一高，就会被当成噪音忽略。
const HTTP_JUDGE_HINTS = ['startsWith(', 'endsWith(', 'replace(', 'includes(', 'indexOf(', '//', 'test('];
for (const f of codeFiles) {
  const text = fs.readFileSync(f, 'utf8');
  text.split('\n').forEach((line, i) => {
    if (!/['"]http:\/\//.test(line)) {
      return;
    }
    if (line.includes('127.0.0.1') || line.includes('localhost')) {
      return;
    }
    if (HTTP_JUDGE_HINTS.some((h) => line.includes(h))) {
      return;
    }
    add('FAIL', 'plaintext-http', f, i + 1, '明文 http 地址：' + line.trim().slice(0, 80));
  });
}

// ---------- 规则 3：日志必须脱敏 ----------
// 任何 hilog/console 直接输出变量（未经 Logger）都可能泄露凭据
for (const f of codeFiles) {
  if (f.includes('platform/Logger.ets')) {
    continue;
  }
  const text = fs.readFileSync(f, 'utf8');
  text.split('\n').forEach((line, i) => {
    if (/\bconsole\.(log|info|warn|error)\s*\(/.test(line)) {
      add('FAIL', 'unsafe-logging', f, i + 1, '绕过 Logger 的 console 输出（不脱敏）');
    }
  });
}

// ---------- 规则 4：C++ 侧的危险函数 ----------
const CPP_DANGER = [
  { re: /\bstrcpy\s*\(/, msg: 'strcpy 无边界' },
  { re: /\bstrcat\s*\(/, msg: 'strcat 无边界' },
  { re: /\bsprintf\s*\(/, msg: 'sprintf 无边界' },
  { re: /\bgets\s*\(/, msg: 'gets 已废弃且无边界' },
  { re: /\bsystem\s*\(/, msg: 'system() 命令注入面' },
];
for (const f of nativeFiles.filter((x) => /\.(cpp|h|cc)$/.test(x))) {
  const text = fs.readFileSync(f, 'utf8');
  text.split('\n').forEach((line, i) => {
    for (const d of CPP_DANGER) {
      if (d.re.test(line) && !line.trim().startsWith('//')) {
        add('FAIL', 'unsafe-c', f, i + 1, d.msg + '：' + line.trim().slice(0, 70));
      }
    }
  });
}

// ---------- 规则 5：凭据不得进 UI 文本/剪贴板以外的持久化 ----------
// 节点凭据必须经 SecretStore；模型字段 credentialRef 只允许放引用
for (const f of codeFiles) {
  const text = fs.readFileSync(f, 'utf8');
  if (!/credentialRef/.test(text)) {
    continue;
  }
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    // 只报"值被带出去"：模板插值 ${...credentialRef...} 或 JSON.stringify 里直接传它。
    // 第一版按"同一行出现 credentialRef 和 Logger"判定，把
    // `Logger.warn('v1 plaintext credentialRef detected')` 这种固定文案也报成泄露——
    // 而那句文案恰恰是"发现明文凭据"的告警本身。
    const leaks = /\$\{[^}]*credentialRef[^}]*\}/.test(line) ||
      /JSON\.stringify\(\s*[^)]*credentialRef/.test(line);
    if (leaks) {
      add('FAIL', 'secret-at-rest', f, i + 1, 'credentialRef 的值被写进落盘/日志');
    }
  });
}

// ---------- 规则 6：导出/分享路径必须走加密 ----------
const bundleFile = path.join(etsDir, 'service/ConfigBundle.ets');
if (fs.existsSync(bundleFile)) {
  const t = fs.readFileSync(bundleFile, 'utf8');
  if (!/AES|GCM|encrypt/i.test(t)) {
    add('FAIL', 'bundle-not-encrypted', bundleFile, 1, '备份导出未见加密实现');
  }
}

// ---------- 规则 7：.gitignore 覆盖敏感产物 ----------
const gi = path.join(ROOT, '.gitignore');
if (fs.existsSync(gi)) {
  const t = fs.readFileSync(gi, 'utf8');
  for (const pat of ['*.jks', '*.p12', '*.keystore', 'local.properties', '.hvigor']) {
    if (!t.includes(pat)) {
      add('WARN', 'gitignore-missing', gi, 1, `.gitignore 未覆盖 ${pat}`);
    }
  }
}

// ---------- 规则 8：自研闸门是否接入 verify ----------
const verify = path.join(scriptsDir, 'verify.ps1');
if (fs.existsSync(verify)) {
  const t = fs.readFileSync(verify, 'utf8');
  for (const gate of ['log-redaction.test.js', 'check-encoding.js', 'check-contrast.js']) {
    if (!t.includes(gate)) {
      add('WARN', 'gate-missing', verify, 1, `verify.ps1 未包含 ${gate}`);
    }
  }
}

// ---------- 输出 ----------
const fails = findings.filter((x) => x.level === 'FAIL');
const warns = findings.filter((x) => x.level === 'WARN');

console.log(`扫描文件：${codeFiles.length} 个 .ets，${nativeFiles.length} 个 native`);
console.log(`结果：FAIL ${fails.length}，WARN ${warns.length}`);
for (const x of findings) {
  console.log(`${x.level}  [${x.rule}]  ${x.file}:${x.line}  ${x.msg}`);
}

if (fails.length > 0 || (STRICT && warns.length > 0)) {
  process.exit(1);
}
console.log('SECURITY PASS');
