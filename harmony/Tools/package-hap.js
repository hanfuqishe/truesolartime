#!/usr/bin/env node
/**
 * 把 hvigor 打出来的 HAP 复制成发布文件名：「真太阳时-鸿蒙-<版本号>.hap」。
 *
 * 版本号取自 AppScope/app.json5 的 versionName（与 Android 的 versionName 保持一致），
 * 输出到仓库根的 dist/（.gitignore 已忽略 *.hap）。
 *
 * 用法：先 `hvigorw ... assembleHap`，再 `node Tools/package-hap.js`。
 * 有签名产物（entry-default-signed.hap）时用它；只有未签名产物时文件名带 -unsigned。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const harmonyRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(harmonyRoot, '..');
const outputDir = path.join(harmonyRoot, 'entry/build/default/outputs/default');
const distDir = path.join(repoRoot, 'dist');

const appJson = fs.readFileSync(path.join(harmonyRoot, 'AppScope/app.json5'), 'utf8');
const version = /"versionName"\s*:\s*"([^"]+)"/.exec(appJson);
if (!version) {
  console.error('AppScope/app.json5 里找不到 versionName');
  process.exit(1);
}

const candidates = [
  { file: 'entry-default-signed.hap', suffix: '' },
  { file: 'entry-default-unsigned.hap', suffix: '-unsigned' },
];
const found = candidates.find((item) => fs.existsSync(path.join(outputDir, item.file)));
if (!found) {
  console.error(`没有找到 HAP 产物，先跑一次 assembleHap：${outputDir}`);
  process.exit(1);
}

fs.mkdirSync(distDir, { recursive: true });
const target = path.join(distDir, `真太阳时-鸿蒙-${version[1]}${found.suffix}.hap`);
fs.copyFileSync(path.join(outputDir, found.file), target);
console.log(`已生成 ${path.relative(repoRoot, target)}`);
