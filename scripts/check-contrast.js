#!/usr/bin/env node
/**
 * scripts/check-contrast.js — 颜色对比度硬闸门（WCAG 2.1）
 *
 * 为什么要脚本而不是"看着还行"：
 *   颜色是这两天才加进来的（协议色标、分组色标、动作色），改一个 hex 就会悄悄
 *   把某个"浅底 + 彩字"的对比度压到 3:1 以下——在室外或低亮度屏幕上直接读不出字，
 *   而开发机的深色背景看起来一切正常。这类问题只能算，不能看。
 *
 * 判据：
 *   正文/标签（小字，<18.66px bold 或 <24px）：≥ 4.5:1
 *   大字与 UI 图形（≥ 24px，或非文本的边框/图标）：≥ 3:1
 *
 * 只检查"成对使用"的颜色（谁压在谁上面），不做全组合暴力配对——
 * 全组合会报一堆永远不会同框的搭配，噪声一多闸门就被忽略。
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const FILES = {
  light: 'entry/src/main/resources/base/element/color.json',
  dark: 'entry/src/main/resources/dark/element/color.json',
};

/** 必须是"成对"的检查项：[前景, 背景, 用途, 最低要求] */
const PAIRS = [
  // 文本层级（浅色/深色都要过）
  ['text_primary', 'bg_canvas', '正文-画布', 4.5],
  ['text_primary', 'bg_surface', '正文-卡片', 4.5],
  ['text_primary', 'bg_surface_alt', '正文-次级卡片', 4.5],
  ['text_secondary', 'bg_canvas', '二级文本-画布', 4.5],
  ['text_secondary', 'bg_surface', '二级文本-卡片', 4.5],
  ['text_secondary', 'bg_surface_alt', '二级文本-次级卡片', 4.5],
  ['text_tertiary', 'bg_surface', '三级文本-卡片', 4.5],
  ['text_tertiary', 'bg_canvas', '三级文本-画布', 4.5],
  // 强调色上的文字
  ['text_on_accent', 'accent', '白字-主蓝', 4.5],
  ['text_on_accent', 'action_probe', '白字-测连通块', 4.5],
  ['text_on_accent', 'action_edit', '白字-编辑块', 4.5],
  ['text_on_accent', 'action_delete', '白字-删除块', 4.5],
  // 状态色作为文字压在自己的浅底上
  ['danger', 'danger_subtle', '危险字-危险底', 4.5],
  ['warning', 'warning_subtle', '警告字-警告底', 4.5],
  ['accent', 'accent_subtle', '强调字-强调底', 4.5],
  // 协议色标：色字压色底
  ['proto_vless', 'proto_vless_bg', 'vless 色标', 4.5],
  ['proto_vmess', 'proto_vmess_bg', 'vmess 色标', 4.5],
  ['proto_trojan', 'proto_trojan_bg', 'trojan 色标', 4.5],
  ['proto_ss', 'proto_ss_bg', 'ss 色标', 4.5],
  // 分组色标
  ['group_a', 'group_a_bg', '分组色标 A', 4.5],
  ['group_b', 'group_b_bg', '分组色标 B', 4.5],
  ['group_c', 'group_c_bg', '分组色标 C', 4.5],
];

function loadColors(rel) {
  const abs = path.join(ROOT, rel);
  const raw = JSON.parse(fs.readFileSync(abs, 'utf8'));
  const map = {};
  for (const item of raw.color) {
    map[item.name] = item.value;
  }
  return map;
}

function parseHex(v) {
  const s = v.trim().replace('#', '');
  if (s.length === 8) {
    // #AARRGGBB：透明通道不参与对比度计算（叠加效果由运行时决定，这里只看实色部分）
    return [parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16), parseInt(s.slice(6, 8), 16)];
  }
  if (s.length === 6) {
    return [parseInt(s.slice(0, 2), 16), parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16)];
  }
  throw new Error(`unsupported color: ${v}`);
}

function channel(c) {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}

function luminance(rgb) {
  return 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2]);
}

function ratio(fg, bg) {
  const l1 = luminance(parseHex(fg));
  const l2 = luminance(parseHex(bg));
  const hi = Math.max(l1, l2);
  const lo = Math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

let failed = 0;
let checked = 0;
const fails = [];

for (const [mode, rel] of Object.entries(FILES)) {
  const colors = loadColors(rel);
  for (const [fg, bg, label, min] of PAIRS) {
    if (!colors[fg] || !colors[bg]) {
      fails.push(`${mode}/${label}: 缺少颜色键 ${!colors[fg] ? fg : bg}`);
      failed++;
      continue;
    }
    const r = ratio(colors[fg], colors[bg]);
    checked++;
    if (r < min) {
      fails.push(`${mode}/${label}: ${fg} on ${bg} = ${r.toFixed(2)}:1 < ${min}:1`);
      failed++;
    }
  }
}

if (failed > 0) {
  console.error(`CONTRAST FAIL: ${failed} 项不达标（共检查 ${checked} 项）`);
  for (const f of fails) {
    console.error('  ' + f);
  }
  process.exit(1);
}

console.log(`CONTRAST PASS: ${checked} 对颜色组合均达到 WCAG 2.1 AA（正文 4.5:1）`);
