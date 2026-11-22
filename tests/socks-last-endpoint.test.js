// tests/socks-last-endpoint.test.js
//
// 目的：锁住 SocksGuard.lastEndpoint() 的三条约束（L-1 / L-2 / L-3）。
//
// 强度说明（不许被读成"行为已验证"）：
//   这里做的是**源码级结构断言**，不是运行期行为断言。原因很实际——SocksGuard 是
//   ArkTS 静态类，且依赖 cryptoFramework，抽不出可在 node 里跑的等价函数体；
//   硬写一份 JS 模拟实现只会变成"测副本"。
//   所以本文件只保证：接口形状对、快照是副本、不落盘、读不改状态。
//   **断开后仍可读**这一条属于运行期行为，只能真机/模拟器手工验证（见 doc/poc/pc12 的验证方式）。
//
// 用法：node tests/socks-last-endpoint.test.js

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'entry', 'src', 'main', 'ets', 'service', 'SocksGuard.ets');
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

// 1) 形状：有 LastEndpoint 类型与 lastEndpoint() 方法，返回可空
check('LastEndpoint 类型存在', /export\s+class\s+LastEndpoint/.test(src));
check('lastEndpoint() 返回可空 LastEndpoint',
  /lastEndpoint\(\)\s*:\s*LastEndpoint\s*\|\s*null/.test(src));

// 2) rotate() 里要写入快照：否则"最近一次"永远是空的
const rotateStart = src.indexOf('static rotate()');
const rotateEnd = src.indexOf('lastEndpoint()', rotateStart);
const rotateBody = rotateStart >= 0 && rotateEnd > rotateStart ? src.slice(rotateStart, rotateEnd) : '';
check('rotate() 内记录快照', /SocksGuard\.last\s*=\s*snap/.test(rotateBody),
  rotateBody === '' ? 'rotate() 未找到' : '未见 SocksGuard.last = snap');

// 3) L-1：返回副本，不是内部引用
const lastStart = src.indexOf('static lastEndpoint()');
const lastBody = lastStart >= 0 ? src.slice(lastStart, src.indexOf('\n  }', lastStart) + 4) : '';
check('lastEndpoint() 构造副本返回', /new\s+LastEndpoint\(\)/.test(lastBody) && /return\s+copy/.test(lastBody));

// 4) L-3：读操作不改状态（函数体内不得赋值 SocksGuard.last / current）
check('lastEndpoint() 只读',
  lastBody.length > 0 && !/SocksGuard\.(last|current)\s*=/.test(lastBody));

// 5) L-3：不落盘、不进日志缓冲、不碰存储层
check('SocksGuard 不依赖持久化层',
  !/KvStore|AppStorage|PersistentStorage|preferences|fileIo/.test(src));

// 6) 口令绝不进快照：快照只允许 host / port 两个字段
const snapBlock = src.slice(src.indexOf('class LastEndpoint'), src.indexOf('export class SocksGuard'));
check('快照只含 host/port，不含凭据',
  /host/.test(snapBlock) && /port/.test(snapBlock) && !/password|user|secret/i.test(snapBlock));

if (failed > 0) {
  console.log(`\n${failed} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed (structural only)');
