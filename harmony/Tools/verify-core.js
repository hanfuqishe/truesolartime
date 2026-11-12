const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const coreDir = path.join(root, 'entry/src/main/ets/core');
const verifyDir = path.join(root, '.verify');
const coreOut = path.join(verifyDir, 'core');

fs.rmSync(verifyDir, { recursive: true, force: true });
fs.mkdirSync(coreOut, { recursive: true });

let count = 0;
for (const name of fs.readdirSync(coreDir)) {
  if (!name.endsWith('.ets')) {
    continue;
  }
  const source = fs.readFileSync(path.join(coreDir, name), 'utf8');
  fs.writeFileSync(path.join(coreOut, name.replace(/\.ets$/, '.ts')), source, 'utf8');
  count++;
}

fs.copyFileSync(path.join(__dirname, 'core-check.ts'), path.join(verifyDir, 'core-check.ts'));

const tsc = require.resolve('typescript/bin/tsc');
const args = [
  tsc,
  '--strict',
  '--target', 'es2020',
  '--module', 'commonjs',
  '--moduleResolution', 'node',
  '--noUnusedLocals',
  '--noImplicitOverride',
  '--skipLibCheck',
  '--outDir', path.join(verifyDir, 'out'),
  path.join(verifyDir, 'core-check.ts')
];
execFileSync(process.execPath, args, { stdio: 'inherit' });
console.log(`compiled ${count} core module(s)`);
execFileSync(process.execPath, [path.join(verifyDir, 'out/core-check.js')], { stdio: 'inherit' });
