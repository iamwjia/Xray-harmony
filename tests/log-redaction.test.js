// tests/log-redaction.test.js
//
// \u76ee\u7684\uff1a\u65e5\u5fd7\u5bfc\u51fa\u524d\u7684\u8131\u654f\u4e0d\u80fd\u9760\u201c\u770b\u7740\u50cf\u5df2\u7ecf\u6253\u7801\u4e86\u201d\u3002
//
// \u4e3a\u4ec0\u4e48\u8981\u6709\u8fd9\u4e2a\u6d4b\u8bd5\uff1a\u65e5\u5fd7\u4f1a\u88ab\u7528\u6237\u622a\u56fe\u3001\u5bfc\u51fa\u3001\u53d1\u5230\u7fa4\u91cc\u3002
// \u4e00\u6761\u6ca1\u88ab\u63a9\u6389\u7684 UUID \u6216\u5bc6\u7801\uff0c\u7b49\u4e8e\u628a\u7528\u6237\u7684\u8282\u70b9\u51ed\u636e\u516c\u5f00\u3002
// \u800c\u8131\u654f\u89c4\u5219\u662f\u6b63\u5219\uff1a\u6539\u4e00\u4e2a\u5b57\u7b26\u5c31\u53ef\u80fd\u6f0f\u6389\u4e00\u6574\u7c7b\uff0c\u800c\u7f16\u8bd1\u4e0d\u4f1a\u62a5\u9519\u3002
//
// \u505a\u6cd5\uff1a\u4ece Logger.ets \u91cc\u62bd\u51fa**\u771f\u5b9e\u7684** redact \u51fd\u6570\u4f53\u6267\u884c\uff08\u4e0d\u662f\u7167\u7740\u5199\u4e00\u4efd\u6a21\u62df\uff09\u3002
// \u7528\u6cd5\uff1anode tests/log-redaction.test.js

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'entry', 'src', 'main', 'ets', 'platform', 'Logger.ets');
const src = fs.readFileSync(SRC, 'utf8');

let failed = 0;
function check(name, cond, detail) {
  if (cond) {
    console.log(`  PASS  ${name}`);
  } else {
    console.log(`  FAIL  ${name}${detail ? ' -> ' + detail : ''}`);
    failed++;
  }
}

/** \u62bd\u51fa redact \u51fd\u6570\u4f53\u5e76\u53bb\u6389 TS \u7c7b\u578b\u6807\u6ce8 */
function loadRedact() {
  const start = src.indexOf('static redact(text: string): string {');
  if (start < 0) throw new Error('redact() not found');
  const braceStart = src.indexOf('{', start);
  // 括号配平必须跳过**正则字面量里的括号**：
  // `[^\s,"'}]` 里的 `}` 会被当成函数体结束，导致抽出来的 body 被截断（实测踩到）。
  let depth = 0;
  let end = -1;
  let inRegex = false;
  let inString = '';
  for (let i = braceStart; i < src.length; i++) {
    const ch = src[i];
    if (inString !== '') {
      if (ch === '\\') {
        i++;
      } else if (ch === inString) {
        inString = '';
      }
      continue;
    }
    if (inRegex) {
      if (ch === '\\') {
        i++;
      } else if (ch === '/') {
        inRegex = false;
      }
      continue;
    }
    if (ch === '/' && src[i + 1] !== '/' && src[i + 1] !== '*') {
      // 前一个非空字符决定这是除法还是正则开头
      let j = i - 1;
      while (j > 0 && /\s/.test(src[j])) j--;
      const prev = src[j];
      if ('(,=:[!&|?{};'.includes(prev)) {
        inRegex = true;
        continue;
      }
    }
    if (ch === '"' || ch === "'" || ch === '`') {
      inString = ch;
      continue;
    }
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) throw new Error('cannot balance redact braces');
  let body = src.slice(braceStart + 1, end);
  body = body.replace(/let s:\s*string\s*=/g, 'let s =');
  const leftover = body.match(/:\s*(string|number|boolean)(\[\])?/g);
  if (leftover) throw new Error('type annotations left: ' + leftover.join(','));
  return new Function('text', body);
}

const redact = loadRedact();

function r(v) {
  return redact(v);
}

console.log('[UUID]');
{
  const uuid = '11111111-2222-3333-4444-555555555555';
  const out = r(`node ${uuid} loaded`);
  check('UUID 被掩盖', out.indexOf(uuid) < 0, out);
  check('UUID 位置留下痕迹', out.indexOf('****') >= 0, out);
}

console.log('[分享链接]');
{
  const link = 'vless://11111111-2222-3333-4444-555555555555@example.org:443#name';
  const out = r(`import ${link}`);
  check('整条链接被打掉', out.indexOf('example.org') < 0 && out.indexOf('11111111') < 0, out);
  check('保留协议名便于排查', out.indexOf('vless://') >= 0, out);
}

console.log('[键值形态的凭据]');
{
  const cases = [
    '{"password":"hunter2"}',
    '{"uuid":"11111111-2222-3333-4444-555555555555"}',
    '{"token":"abc.def"}',
    '{"secret":"s3cr3t"}',
    '{"pbk":"pubkeymaterial"}'
  ];
  for (const c of cases) {
    const out = r(c);
    check(`字段被掩盖: ${c}`, /"password":"hunter2"|"uuid":"11111111|"token":"abc\.def"|"secret":"s3cr3t"|"pbk":"pubkey/.test(out) === false, out);
  }
}

console.log('[非 JSON 形态的凭据（常见于拼接口令的日志）]');
{
  const cases = [
    'password=hunter2',
    'pwd=hunter2',
    'token=abc.def',
    'passwd: hunter2'
  ];
  for (const c of cases) {
    const out = r(c);
    check(`无引号也应掩盖: ${c}`, out.indexOf('hunter2') < 0 && out.indexOf('abc.def') < 0, out);
  }
}

console.log('[服务器地址]');
{
  const out = r('connect to 10.0.2.2:10443 ok');
  check('IPv4 被掩盖', out.indexOf('10.0.2.2') < 0, out);
  const out2 = r('proxy/freedom: connection opened to 1.1.1.1:53');
  check('IPv4+端口被掩盖', out2.indexOf('1.1.1.1') < 0, out2);
}

console.log('[不应过度掩盖：诊断信息要保得住]');
{
  const out = r('KernelService.start bytes=984 confirmed running=true');
  check('普通诊断文本不变', out === 'KernelService.start bytes=984 confirmed running=true', out);
  const out3 = r('socks endpoint rotated: 127.0.0.1:39512 (auth=password)');
  check('模式词不被误掩（auth=password）', out3.indexOf('auth=password') >= 0, out3);
  const out2 = r('socks endpoint rotated: 127.0.0.1:39512');
  check('端口仍可读（排障必需）', out2.indexOf('39512') >= 0, out2);
}

console.log('[报告入口]');
{
  check('buildReport 存在', src.indexOf('static buildReport(') >= 0);
  check('报告写明已脱敏', src.indexOf('\u5df2\u8131\u654f') >= 0 || src.indexOf('\u8131\u654f') >= 0);
  // \u5199\u5165\u7f13\u51b2\u533a\u7684\u5730\u65b9\u5fc5\u987b\u8c03 redact\uff0c\u5426\u5219\u5bfc\u51fa\u65f6\u518d\u8131\u654f\u5c31\u665a\u4e86
  check('push 时即脱敏（不是导出时才做）', /e\.msg\s*=\s*Logger\.redact\(/.test(src));
}

console.log('');
if (failed === 0) {
  console.log('ALL PASS');
  process.exit(0);
}
console.log(`${failed} FAILED`);
process.exit(1);
