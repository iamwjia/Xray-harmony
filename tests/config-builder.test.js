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
  // 语义变更（2026-11-22）：全局模式之前不生成 routing，结果是“全部流量走代理、
  // 但 DNS 仍在本机解析”——域名仍会泄露。现在固定带一条 53 → proxy。
  check('GLOBAL 只带一条 DNS 规则', cfg.routing.rules.length === 1, JSON.stringify(cfg.routing));
  check('GLOBAL 的 DNS 走代理', cfg.routing.rules[0].outboundTag === 'proxy' &&
    cfg.routing.rules[0].port === '53');
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
  // 期望顺序：DNS / user(example.org) / user(10.1.0.0/16) / geosite / geoip+lan
  // DNS 必须排第一：否则国内域名的查询会被 geosite 先命中成直连
  check('规则条数 = 5（DNS + 2 条自定义 + geosite + geoip）', rules.length === 5, rules.length);
  check('第一条是 DNS 走代理', rules[0].port === '53' && rules[0].outboundTag === 'proxy');
  check('第二条是用户规则（必须在 geo 之前）', rules[1].domain && rules[1].domain[0] === 'example.org');
  check('启用的 block 规则保留', rules[2].ip && rules[2].ip[0] === '10.1.0.0/16' && rules[2].outboundTag === 'block');
  check('禁用的规则被跳过', !JSON.stringify(rules).includes('disabled.example'));
  check('空模式被跳过', !JSON.stringify(rules).includes('"domain":[""]'));
  check('geosite:cn 在用户规则之后', JSON.stringify(rules[3]).includes('geosite:cn'));
  check('geoip:cn 与内网网段在最后', JSON.stringify(rules[4]).includes('geoip:cn') &&
    JSON.stringify(rules[4]).includes('192.168.0.0/16'));
  check('RULE 使用 IPIfNonMatch', cfg.routing.domainStrategy === 'IPIfNonMatch');
}

console.log('[RULE · geo 资源缺失时应降级]');
{
  const cfg = JSON.parse('{"outbounds":[]' + buildRouting(ROUTING_MODE.RULE, false, []) + '}');
  const rules = cfg.routing.rules;
  // 降级时 DNS 规则仍在：它不依赖 geo 资源，且它正是防泄露的那一条
  check('降级后为 DNS + 内网直连两条', rules.length === 2, rules.length);
  check('降级后内网直连仍在最后', rules[1].outboundTag === 'direct');
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
  // 只监听回环这件事现在只有一个来源（SocksGuard.LOCAL_HOST），
  // 所以断言不再是"某处有字面量"，而是"字面量只有一处、且这里确实用它"。
  const guardSrc = fs.readFileSync(
    path.join(ROOT, 'entry', 'src', 'main', 'ets', 'service', 'SocksGuard.ets'), 'utf8');
  // 注释里提到这个地址是允许的（说明性文字），只算代码行
  const guardCode = guardSrc.split('\n')
    .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
    .join('\n');
  check('回环地址代码里只定义一处',
    (guardCode.match(/127\.0\.0\.1/g) || []).length === 1,
    'LOCAL_HOST 之外不应再有硬编码的回环地址');
  check('入站监听取统一常量',
    src.includes('"listen":"\' + SocksGuard.LOCAL_HOST') && !src.includes('"listen":"127.0.0.1"'));
}

// ---------------------------------------------------------------- 出站：行为级
// 背景：四个协议的出站都该带 streamSettings（出站流控由 outbound handler 统一套用，
// 与协议无关）。shadowsocks 分支曾经漏拼，表现是"给 ss 节点选了 WS，保存成功、实际按 TCP 走"，
// 编译不报错、内核也不报错，只能靠断言拦。
console.log('[出站：四个协议都要带 streamSettings]');
{
  // 抽取 buildOutbound 里 shadowsocks 分支的真实函数体，喂假参数跑一遍
  const start = src.indexOf("if (proto === 'shadowsocks') {");
  const end = src.indexOf("return '{\"tag\":\"proxy\",\"protocol\":\"freedom\"}';");
  check('能定位到 shadowsocks 分支', start > 0 && end > start);

  if (start > 0 && end > start) {
    const rawBody = src.slice(start + "if (proto === 'shadowsocks') {".length, end).trim();
    // 截到 freedom 的 return 之前，尾部还留着 ss 分支自己的收尾 `}`，去掉它
    const noTrailing = rawBody.replace(/\}\s*$/, '').trim();
    // ArkTS 的类型标注 JS 不认，先剥掉再交给 new Function 执行（与上面 buildRouting 同一手法）
    const body = noTrailing.replace(/:\s*(string|number|boolean)\b/g, '');
    const KC = { esc: (v) => JSON.stringify(v) };
    // eslint-disable-next-line no-new-func
    const run = new Function('addr', 'port', 'cred', 'stream', 'KernelConfigBuilder', body);

    const streamJson = '{"network":"ws","security":"tls","wsSettings":{"path":"/x"}}';
    const out = JSON.parse(run('"h.example"', 8388, 'aes-256-gcm:pw', streamJson, KC));
    check('ss 出站带 streamSettings', out.streamSettings !== undefined);
    check('ss 的 streamSettings 原样透传（network=ws）',
      out.streamSettings && out.streamSettings.network === 'ws',
      JSON.stringify(out.streamSettings));
    check('ss 的 method 与 password 按首个冒号拆分',
      out.settings.servers[0].method === 'aes-256-gcm' &&
      out.settings.servers[0].password === 'pw',
      JSON.stringify(out.settings.servers[0]));

    // 不带冒号的凭据（只有 password）：method 回落 aes-256-gcm，password 取全串
    const out2 = JSON.parse(run('"h.example"', 8388, 'only-password', streamJson, KC));
    check('无冒号凭据回落默认 method',
      out2.settings.servers[0].method === 'aes-256-gcm' &&
      out2.settings.servers[0].password === 'only-password',
      JSON.stringify(out2.settings.servers[0]));

    // 另外三个分支：源码级断言（它们是拼接串，行为级抽取成本高）
    ['vless', 'vmess', 'trojan'].forEach((p) => {
      const s = src.indexOf(`if (proto === '${p}') {`);
      const e = src.indexOf('return ', s);
      const seg = src.slice(s, src.indexOf(';', e));
      check(`${p} 出站带 streamSettings`, seg.includes('"streamSettings":'));
    });
  }
}

console.log('');
if (failed === 0) {
  console.log('ALL PASS');
  process.exit(0);
}
console.log(`${failed} FAILED`);
process.exit(1);
