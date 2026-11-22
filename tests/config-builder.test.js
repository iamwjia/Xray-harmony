// tests/config-builder.test.js
//
// 目的：把「内核配置生成」这类纯逻辑纳入自动回归。
// 为什么专挑这块：分流的顺序、出站的字段、入站的鉴权与 UDP，全是手拼字符串。
// 拼错一个逗号或把规则顺序写反，编译不会报错、内核也可能照跑，但行为是错的
// —— 这类 bug 只能靠断言拦住。
//
// 做法分两级，强度不同，注释里写清楚，避免误以为它们等价：
//   1) 行为级：从 .ets 源码里抽出 buildRouting 的 return 表达式，拼成完整配置后
//      JSON.parse 并断言语义（等价于跑真实分支，是强断言）；
//   2) 源码级：入站片段是变量拼接，抽不出来，只能断言源码里存在关键片段
//      （弱断言，仅防"被手滑改回去"，不证明行为）。
//
// 用法： node tests/config-builder.test.js

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'entry', 'src', 'main', 'ets', 'service', 'KernelConfigBuilder.ets');
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

// ---------------------------------------------------------------- 行为级
function extractRoutingFragments() {
  const start = src.indexOf('private static buildRouting');
  const end = src.indexOf('private static buildOutbound', start);
  if (start < 0 || end < 0) {
    throw new Error('buildRouting / buildOutbound markers not found');
  }
  const body = src.slice(start, end);
  const re = /return\s+([\s\S]*?);/g;
  const exprs = [];
  let m;
  while ((m = re.exec(body)) !== null) {
    if (m[1].trim() === '') continue;
    exprs.push(m[1]);
  }
  // 源码顺序：DIRECT, GLOBAL, 然后是 RULE（RULE 分支里有循环，取最后一段 return）
  return exprs;
}

const exprs = extractRoutingFragments();
// DIRECT / GLOBAL 是字面量，直接求值即为真实分支
const directFrag = eval(exprs[0]);
const globalFrag = eval(exprs[1]);

/**
 * 取 buildRouting 的真实函数体，去掉 TS 类型标注后交给 JS 执行。
 *
 * 为什么不再"照着源码写一份模拟"：那样测的是副本。副本与真实代码一旦不同步，
 * 测试会继续通过——这正是我们最不能接受的失败模式。所以这里直接跑源码。
 */
function loadBuildRouting() {
  const start = src.indexOf('private static buildRouting');
  const braceStart = src.indexOf('{', start);
  // 花括号配平，找到函数体结束位置
  let depth = 0;
  let end = -1;
  for (let i = braceStart; i < src.length; i++) {
    const ch = src[i];
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) throw new Error('cannot balance buildRouting braces');
  let body = src.slice(braceStart + 1, end);

  // 去类型标注（只针对这个函数体里出现的形态，刻意保守）
  body = body
    .replace(/const parts:\s*string\[\]\s*=/g, 'const parts =')
    .replace(/const r:\s*RoutingRule\s*=/g, 'const r =')
    .replace(/let tag:\s*string\s*=/g, 'let tag =')
    .replace(/const field:\s*string\s*=/g, 'const field =')
    .replace(/const lan:\s*string\s*=/g, 'const lan =')
    .replace(/const ipRule:\s*string\s*=/g, 'const ipRule =')
    .replace(/KernelConfigBuilder\.esc\(/g, 'esc(');

  // 未去掉的类型标注直接报错，而不是静默产出错误结果
  const leftover = body.match(/:\s*(string|number|boolean|RoutingRule)(\[\])?/g);
  if (leftover) {
    throw new Error('type annotations left in extracted body: ' + leftover.join(', '));
  }

  const factory = new Function('mode', 'geoReady', 'userRules', 'RoutingMode', 'esc', body);
  return (mode, geoReady, userRules) => factory(mode, geoReady, userRules, ROUTING_MODE, (v) => JSON.stringify(v));
}

const ROUTING_MODE = { DIRECT: 'direct', GLOBAL: 'global', RULE: 'rule' };
const buildRouting = loadBuildRouting();

console.log('[DIRECT]');
{
  const cfg = JSON.parse('{"outbounds":[]' + buildRouting(ROUTING_MODE.DIRECT, true, []) + '}');
  check('DIRECT 只有一条规则', cfg.routing.rules.length === 1);
  check('DIRECT 全部直连', cfg.routing.rules[0].outboundTag === 'direct');
  check('DIRECT 覆盖 tcp,udp', cfg.routing.rules[0].network === 'tcp,udp');
}

console.log('[GLOBAL]');
{
  const cfg = JSON.parse('{"outbounds":[]' + buildRouting(ROUTING_MODE.GLOBAL, true, []) + '}');
  check('GLOBAL 不生成 routing 段', cfg.routing === undefined);
}

console.log('[RULE]');
{
  const userRules = [
    { enabled: true, pattern: 'example.org', matchType: 'domain', action: 'direct' },
    { enabled: false, pattern: 'disabled.example', matchType: 'domain', action: 'block' },
    { enabled: true, pattern: '', matchType: 'domain', action: 'proxy' },
    { enabled: true, pattern: '10.1.0.0/16', matchType: 'ip', action: 'block' }
  ];
  const cfg = JSON.parse('{"outbounds":[]' + buildRouting(ROUTING_MODE.RULE, true, userRules) + '}');
  const rules = cfg.routing.rules;
  // 期望顺序：user(example.org) / user(10.1.0.0/16) / geosite / geoip+lan
  check('规则条数 = 4（2 条自定义 + geosite + geoip）', rules.length === 4, rules.length);
  check('第一条是用户规则（必须先匹配）', rules[0].domain && rules[0].domain[0] === 'example.org');
  check('启用的 block 规则保留', rules[1].ip && rules[1].ip[0] === '10.1.0.0/16' && rules[1].outboundTag === 'block');
  check('禁用的规则被跳过', !JSON.stringify(rules).includes('disabled.example'));
  check('空模式被跳过', !JSON.stringify(rules).includes('"domain":[""]'));
  check('geosite:cn 在用户规则之后', JSON.stringify(rules[2]).includes('geosite:cn'));
  check('geoip:cn 与内网网段在最后', JSON.stringify(rules[3]).includes('geoip:cn') &&
    JSON.stringify(rules[3]).includes('192.168.0.0/16'));
  check('RULE 使用 IPIfNonMatch', cfg.routing.domainStrategy === 'IPIfNonMatch');
}

console.log('[RULE · geo 资源缺失时应降级]');
{
  const cfg = JSON.parse('{"outbounds":[]' + buildRouting(ROUTING_MODE.RULE, false, []) + '}');
  const rules = cfg.routing.rules;
  check('降级后只有一条内网直连规则', rules.length === 1, rules.length);
  check('降级后不再引用 geosite/geoip（否则内核启动即失败）',
    !JSON.stringify(cfg).includes('geosite:') && !JSON.stringify(cfg).includes('geoip:'));
}

// ---------------------------------------------------------------- 源码级
console.log('[入站片段：源码级断言]');
{
  check('SOCKS 入站开启 udp（否则 QUIC/DNS 无出口）',
    (src.match(/"udp":true/g) || []).length === 2,
    'expected 2 occurrences of "udp":true');
  check('有口令时使用 password 鉴权',
    src.includes('"auth":"password"') && src.includes('"accounts"'));
  check('无口令时回落 noauth', src.includes('"auth":"noauth"'));
  check('入站只监听回环', src.includes('"listen":"127.0.0.1"'));
}

console.log('');
if (failed === 0) {
  console.log('ALL PASS');
  process.exit(0);
}
console.log(`${failed} FAILED`);
process.exit(1);
