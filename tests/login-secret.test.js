'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { digits, loginSecret, OK } = require('../assets/login-secret.js');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

test('13-digit national IDs keep digits only', () => {
  const cases = [
    '0000000000000',
    '  0000000000000  ',
    '0-0000-00000-00-0',
    '0 0000 00000 00 0',
    '0.0000.00000.00.0',
    '๐๐๐๐๐๐๐๐๐๐๐๐๐',
    '๐-๐๐๐๐-๐๐๐๐๐-๐๐-๐',
    '๐ ๐๐๐๐ ๐๐๐๐๐ ๐๐ ๐',
    '0–0000–00000–00–0',
  ];
  for (const raw of cases) {
    assert.equal(loginSecret(raw), '0000000000000', raw);
    assert.equal(OK.test(loginSecret(raw)), true, raw);
  }
});

test('letter + 12 digits keeps the leading letter and uppercases it', () => {
  const cases = [
    'A000000000000',
    'a000000000000',
    'a-0000-0000-0000',
    'A 0000 0000 0000',
    'a.0000.0000.0000',
    'a๐๐๐๐๐๐๐๐๐๐๐๐',
    '  a - ๐๐๐-๐๐๐-๐๐๐-๐๐๐ ',
    'A–0000–0000–0000',
  ];
  for (const raw of cases) {
    assert.equal(loginSecret(raw), 'A000000000000', raw);
    assert.equal(OK.test(loginSecret(raw)), true, raw);
  }
  // The old digits-only cleanup drops the letter and would be rejected as 12 digits.
  assert.equal(digits('A000000000000'), '000000000000');
  assert.notEqual(loginSecret('A000000000000'), digits('A000000000000'));
});

test('a leading letter that is not + 12 digits is not stripped into a national ID', () => {
  assert.equal(loginSecret('A0000000000000'), 'A0000000000000');
  assert.equal(OK.test(loginSecret('A0000000000000')), false);
  assert.equal(loginSecret('AB000000000000'), 'AB000000000000');
  assert.equal(OK.test(loginSecret('AB000000000000')), false);
  assert.equal(loginSecret('A00000000000'), 'A00000000000');
  assert.equal(OK.test(loginSecret('')), false);
  assert.equal(OK.test(loginSecret('000000000000')), false);
});

test('student code cleanup is unchanged', () => {
  assert.equal(digits('00000'), '00000');
  assert.equal(digits('๐๐๐๐๐'), '00000');
  assert.equal(digits('00-000'), '00000');
  assert.equal(digits('00 000'), '00000');
  assert.equal(digits(' ๐๐-๐๐๐ '), '00000');
});

test('frontend wires both formats and cache-busts the new scripts', () => {
  const game = read('assets/game.js');
  const html = read('index.html');
  const sw = read('sw.js');
  assert.match(game, /loginSecret\(\$\('#p'\)\.value\)/);
  assert.doesNotMatch(game, /digits\(\$\('#p'\)\.value\)/);
  assert.match(game, /เลขบัตรประชาชน หรือรหัสประจำตัว/);
  assert.match(game, /inputmode="text"/);
  assert.match(game, /serviceWorker\.register\('sw\.js'\)/);
  assert.match(html, /assets\/login-secret\.js\?v=1/);
  assert.match(html, /assets\/game\.js\?v=15/);
  assert.doesNotMatch(html, /game\.js\?v=14/);
  assert.match(sw, /const V='kv-2\.4\.0'/);
  assert.match(sw, /assets\/login-secret\.js\?v=1/);
  assert.match(sw, /assets\/game\.js\?v=15/);
  assert.doesNotMatch(sw, /game\.js\?v=14/);
});
