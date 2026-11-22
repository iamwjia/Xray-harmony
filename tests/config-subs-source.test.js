#!/usr/bin/env node
/**
 * tests/config-subs-source.test.js — 订阅条数只能从 SubscriptionStore 读
 *
 * 事故：首页入口格与设置页的"订阅 N 个"，读的是 `AppConfig.subscriptions`。
 * 那个字段从来没被填充过（订阅一直存在 SubscriptionStore），于是"订阅管理里有 3 条"
 * 而首页显示"未添加"。这类"读了一个永远是空的字段"的 bug 不会报错、不会崩，
 * 只会安静地显示错误信息，只能靠闸门兜住。
 *
 * 规则：源码里出现 `getConfig().subscriptions` 即失败。
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'entry/src/main/ets');

function walk(dir, out) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const st = fs.statSync(full);
    if (st.isDirectory()) {
      walk(full, out);
    } else if (name.endsWith('.ets')) {
      out.push(full);
    }
  }
}

const files = [];
walk(SRC, files);

const bad = [];
for (const f of files) {
  const text = fs.readFileSync(f, 'utf8');
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    if (line.includes('getConfig().subscriptions')) {
      bad.push(`${path.relative(ROOT, f)}:${i + 1}  ${line.trim()}`);
    }
  });
}

if (bad.length > 0) {
  console.error('CONFIG-SUBS FAIL: 订阅条数读了一个永远为空的字段（应读 SubscriptionService.listSubscriptions 或 SubscriptionStore.load）');
  for (const b of bad) {
    console.error('  ' + b);
  }
  process.exit(1);
}

console.log(`CONFIG-SUBS PASS: ${files.length} 个源文件均未误用 AppConfig.subscriptions`);
