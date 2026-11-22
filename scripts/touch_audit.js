// \u4e00\u6b21\u6027\u5ba1\u8ba1\uff1a\u626b\u63cf\u9875\u9762/\u7ec4\u4ef6\u91cc\u7684\u201c\u684c\u9762\u601d\u7ef4\u201d\u4fe1\u53f7
// \u8f93\u51fa\u7528\u4e8e\u4eba\u5de5\u5224\u65ad\uff0c\u4e0d\u505a\u81ea\u52a8\u4fee\u6539
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', 'entry', 'src', 'main', 'ets');
const dirs = ['pages', 'components'];

const findings = {
  textClickNoHit: [],   // Text \u4e0a\u76f4\u63a5 onClick\uff08\u53ef\u80fd\u547d\u4e2d\u533a <44\uff09
  smallHeight: [],      // \u53ef\u70b9\u5143\u7d20\u9ad8\u5ea6\u5b57\u9762\u91cf <44
  noPressed: [],        // \u53ef\u70b9\u5143\u7d20\u4e0d\u5e26\u6309\u4e0b\u53cd\u9988\uff08stateStyles / .onTouch\uff09
  inputNoSubmit: [],    // TextInput \u65e0 onSubmit
  hit44: 0,
};

function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const full = path.join(dir, f);
    if (fs.statSync(full).isDirectory()) {
      walk(full);
      continue;
    }
    if (!f.endsWith('.ets')) continue;
    const src = fs.readFileSync(full, 'utf8');
    const rel = path.relative(ROOT, full);
    const lines = src.split('\n');

    lines.forEach((ln, i) => {
      if (/\.onClick\(/.test(ln) && /^\s*Text\(/.test(ln)) {
        findings.textClickNoHit.push(`${rel}:${i + 1}`);
      }
      if (/\.height\((\d+)\)/.test(ln)) {
        const m = ln.match(/\.height\((\d+)\)/);
        const h = parseInt(m[1], 10);
        if (h < 44 && h > 14) findings.smallHeight.push(`${rel}:${i + 1} h=${h}`);
        if (h === 44) findings.hit44++;
      }
    });

    const clickCount = (src.match(/\.onClick\(/g) || []).length;
    const pressedCount = (src.match(/stateStyles|\.onTouch\(/g) || []).length;
    if (clickCount > 0 && pressedCount === 0) {
      findings.noPressed.push(`${rel} (onClick=${clickCount})`);
    }
    const inputs = (src.match(/TextInput\(/g) || []).length;
    const submits = (src.match(/\.onSubmit\(/g) || []).length;
    if (inputs > submits) findings.inputNoSubmit.push(`${rel} input=${inputs} submit=${submits}`);
  }
}

for (const d of dirs) walk(path.join(ROOT, d));

console.log('=== Text 上直接 onClick（需人工看命中区） ===');
findings.textClickNoHit.forEach((x) => console.log('  ' + x));
console.log('=== 高度字面量 <44 的可点元素 ===');
findings.smallHeight.forEach((x) => console.log('  ' + x));
console.log('=== 有 onClick 但无按下反馈 ===');
findings.noPressed.forEach((x) => console.log('  ' + x));
console.log('=== TextInput 无 onSubmit ===');
findings.inputNoSubmit.forEach((x) => console.log('  ' + x));
console.log('');
console.log('hit(44) \u51fa\u73b0\u6b21\u6570 =', findings.hit44);
