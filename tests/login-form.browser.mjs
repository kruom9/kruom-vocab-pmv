// Headless login-form check. Synthetic IDs only. Supabase is intercepted and never contacted.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const { loginSecret } = require('../assets/login-secret.js');

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const shots = '/opt/cursor/artifacts';

function contentType(file) {
  const ext = path.extname(file);
  return ({
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.webmanifest': 'application/manifest+json',
    '.png': 'image/png',
    '.woff': 'font/woff',
    '.webp': 'image/webp',
    '.json': 'application/json',
  })[ext] || 'application/octet-stream';
}

function startServer() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    const rel = decodeURIComponent(url.pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, rel);
    if (file !== root && !file.startsWith(root + path.sep)) {
      res.writeHead(403).end();
      return;
    }
    fs.readFile(file, (err, data) => {
      if (err) {
        res.writeHead(404).end('missing');
        return;
      }
      res.writeHead(200, { 'Content-Type': contentType(file), 'Cache-Control': 'no-store' });
      res.end(data);
    });
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const calls = [];

async function main() {
  fs.mkdirSync(shots, { recursive: true });
  const server = await startServer();
  const base = `http://127.0.0.1:${server.address().port}/`;
  const browser = await chromium.launch({
    channel: 'chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  await page.route('**/*', async (route) => {
    const url = route.request().url();
    let host = '';
    try { host = new URL(url).hostname; } catch (e) { host = ''; }
    if (host.endsWith('supabase.co')) {
      calls.push({ url, method: route.request().method(), body: route.request().postData() });
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'BAD_LOGIN' }),
      });
      return;
    }
    if (host && host !== '127.0.0.1' && host !== 'localhost') {
      await route.abort();
      return;
    }
    await route.continue();
  });

  const failures = [];
  page.on('pageerror', (err) => failures.push(String(err)));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('#p');
  await page.waitForSelector('#c');

  const ui = await page.evaluate(() => {
    const p = document.querySelector('#p');
    const c = document.querySelector('#c');
    const labels = [...document.querySelectorAll('label')].map((el) => el.childNodes[0].textContent.trim());
    return {
      labels,
      help: document.querySelector('.mut').textContent,
      placeholder: p.getAttribute('placeholder'),
      inputmode: p.getAttribute('inputmode'),
      type: p.getAttribute('type'),
      codeMode: c.getAttribute('inputmode'),
      secret: window.__vocab.loginSecret('a-๐๐๐๐-๐๐๐๐-๐๐๐๐'),
      numeric: window.__vocab.loginSecret('๐-๐๐๐๐-๐๐๐๐๐-๐๐-๐'),
    };
  });
  assert.deepEqual(ui.labels, ['เลขประจำตัวนักเรียน (5 หลัก)', 'เลขบัตรประชาชน หรือรหัสประจำตัว']);
  assert.match(ui.help, /13 หลัก/);
  assert.match(ui.help, /12 หลัก/);
  assert.match(ui.help, /ขีดหรือเว้นวรรค/);
  assert.match(ui.placeholder, /13 หลัก/);
  assert.match(ui.placeholder, /12 หลัก/);
  assert.equal(ui.inputmode, 'text');
  assert.equal(ui.type, 'password');
  assert.equal(ui.codeMode, 'numeric');
  assert.equal(ui.secret, 'A000000000000');
  assert.equal(ui.numeric, '0000000000000');
  assert.equal(ui.secret, loginSecret('a-๐๐๐๐-๐๐๐๐-๐๐๐๐'));

  await page.screenshot({ path: path.join(shots, 'login-mobile.png'), fullPage: true });
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.screenshot({ path: path.join(shots, 'login-desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });

  await page.locator('#p').focus();
  await page.locator('#p').pressSequentially('A');
  assert.equal(await page.locator('#p').inputValue(), 'A');

  async function submit(code, secret) {
    await page.waitForFunction(() => {
      const b = document.querySelector('#go');
      return b && !b.disabled;
    });
    const before = calls.length;
    await page.fill('#c', code);
    await page.fill('#p', secret);
    await page.click('#go');
    await page.waitForFunction(() => {
      const e = document.querySelector('#e');
      return !!(e && e.textContent.trim());
    }, null, { timeout: 3000 });
    const err = ((await page.locator('#e').textContent()) || '').trim();
    const fresh = calls.slice(before);
    return { err, bodies: fresh.map((c) => JSON.parse(c.body)), urls: fresh.map((c) => c.url) };
  }

  let r = await submit('0000', '0000000000000');
  assert.equal(r.err, 'เลขประจำตัวนักเรียนต้องมี 5 หลัก');
  assert.equal(r.bodies.length, 0);

  r = await submit('00000', '000000000000');
  assert.equal(r.err, 'กรุณาใส่เลขบัตรประชาชน 13 หลัก หรือรหัสตัวอักษร 1 ตัวตามด้วยเลข 12 หลัก');
  assert.equal(r.bodies.length, 0);

  r = await submit('00000', 'A0000000000000');
  assert.equal(r.err, 'กรุณาใส่เลขบัตรประชาชน 13 หลัก หรือรหัสตัวอักษร 1 ตัวตามด้วยเลข 12 หลัก');
  assert.equal(r.bodies.length, 0);
  await page.screenshot({ path: path.join(shots, 'login-format-error.png'), fullPage: true });

  r = await submit('๐๐๐๐๐', '๐-๐๐๐๐-๐๐๐๐๐-๐๐-๐');
  assert.equal(r.err, 'เลขประจำตัวนักเรียนหรือเลขบัตรประชาชน/รหัสประจำตัวไม่ถูกต้อง');
  assert.deepEqual(r.bodies, [{ p_code: '00000', p_password: '0000000000000' }]);
  assert.ok(r.urls.every((u) => u.endsWith('/rpc/vocab_login')));

  r = await submit('00-000', '0 0000 00000 00 0');
  assert.deepEqual(r.bodies, [{ p_code: '00000', p_password: '0000000000000' }]);

  r = await submit('00 000', 'a-0000-0000-0000');
  assert.deepEqual(r.bodies, [{ p_code: '00000', p_password: 'A000000000000' }]);

  r = await submit('00000', '  A ๐๐๐-๐๐๐-๐๐๐-๐๐๐ ');
  assert.deepEqual(r.bodies, [{ p_code: '00000', p_password: 'A000000000000' }]);
  assert.ok(calls.every((c) => c.method === 'POST' && c.url.includes('/rest/v1/rpc/vocab_login')));
  assert.equal(failures.length, 0, failures.join('\n'));

  await browser.close();
  await new Promise((resolve, reject) => server.close((err) => err ? reject(err) : resolve()));
  console.log('login form ok', calls.length, 'intercepted vocab_login calls');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
