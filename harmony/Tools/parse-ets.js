/**
 * 用 TypeScript 的解析器检查「纯逻辑」ArkTS 文件的语法。
 *
 * 这些文件（core / services / 两个 Ability）不含 ArkUI 声明式 DSL，语法上是 TypeScript 的子集，
 * 因此可以脱离鸿蒙 SDK 做真正的语法解析；页面与卡片里的 `Column() { ... }` 不行，
 * 那部分只能在 DevEco Studio 里编译验证。
 */

const fs = require('fs');
const path = require('path');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const targets = ['core', 'services', 'entryability', 'entryformability'];

let checked = 0;
const problems = [];

for (const folder of targets) {
  const dir = path.join(root, folder);
  if (!fs.existsSync(dir)) {
    continue;
  }
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith('.ets')) {
      continue;
    }
    const file = path.join(dir, name);
    const text = fs.readFileSync(file, 'utf8');
    const source = ts.createSourceFile(file, text, ts.ScriptTarget.ES2021, true, ts.ScriptKind.TS);
    checked++;
    for (const diagnostic of source.parseDiagnostics) {
      const position = source.getLineAndCharacterOfPosition(diagnostic.start);
      const message = ts.flattenDiagnosticMessageText(diagnostic.messageText, ' ');
      problems.push(`${folder}/${name}:${position.line + 1}:${position.character + 1}: ${message}`);
    }
  }
}

console.log(`parsed ${checked} ArkTS file(s)`);
if (problems.length > 0) {
  for (const problem of problems) {
    console.log(`  ERROR ${problem}`);
  }
  process.exit(1);
}
console.log('no syntax errors found');
