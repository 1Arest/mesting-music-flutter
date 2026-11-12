/* Browser-only protocol verification; never evaluate collected scripts in the
 * Node process. Usage: node verify_lx_source_bridge.cjs <playwright module path>
 * <Chrome executable> <output directory>. The browser uses a fresh ephemeral
 * profile, blocks real network, and closes every Worker and page after testing.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require(process.argv[2] || 'playwright');
const root = path.resolve(__dirname, '../third_party/lx_music_source');
const output = process.argv[4];
const csp = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; worker-src blob:; connect-src 'none'; base-uri 'none'; form-action 'none'";
const bridge = fs.readFileSync(path.join(root, 'bridge.js'), 'utf8');
const crypto = fs.readFileSync(path.join(root, 'crypto-js/crypto-js.js'), 'utf8');
const host = fs.readFileSync(path.join(root, 'host.js'), 'utf8');
(async () => {
  const browser = await chromium.launch({ executablePath: process.argv[3], headless: true });
  const reports = [];
  async function run(name, script, check) {
    const page = await browser.newPage();
    const messages = [];
    let directNetwork = 0;
    await page.route('**/*', route => { directNetwork++; return route.abort(); });
    await page.exposeFunction('hostMessage', text => messages.push(JSON.parse(text)));
    await page.setContent(`<html><meta http-equiv="Content-Security-Policy" content="${csp}"></html>`);
    await page.evaluate(() => { self.MestingLx = { postMessage: text => self.hostMessage(text) }; });
    await page.addScriptTag({ content: host });
    await page.evaluate(code => MestingLxHost.start(code.script, code.bridge, code.crypto), { script, bridge, crypto });
    try {
      await check(page, messages);
      assert.equal(directNetwork, 0, 'Workers must not open ordinary network channels');
      reports.push({ name, passed: true, directNetwork });
      process.stdout.write(`${name}: passed\n`);
    } finally { await page.close(); }
  }
  async function tick(page, messages, predicate, limit = 3000) {
    const started = Date.now();
    while (!predicate() && Date.now() - started < limit) {
      for (const message of messages.filter(m => m.kind === 'request' && !m.handled)) {
        message.handled = true;
        await page.evaluate(id => MestingLxHost.respond(id, null, {
          statusCode: 200, headers: { 'content-type': 'application/json' },
          body: { code: 200, version: '0.0.0', data: {} },
        }), message.id);
      }
      await page.waitForTimeout(20);
    }
    assert(predicate(), 'expected protocol event before timeout');
  }
  try {
    for (const file of fs.readdirSync(path.join(root, 'scripts'))) {
      await run(`${file}: initialization`, fs.readFileSync(path.join(root, 'scripts', file), 'utf8'), async (page, messages) => {
        await tick(page, messages, () => messages.some(m => m.kind === 'ready'));
        assert(messages.find(m => m.kind === 'ready').qualities.includes('128k'));
      });
    }
    await run('crypto and Unicode buffer vectors', `
      lx.on('request', async () => {
        const buf = lx.utils.buffer.from('音乐', 'utf-8');
        const base64 = lx.utils.buffer.bufToString(buf, 'base64');
        const digest = lx.utils.crypto.md5('abc');
        const encrypted = lx.utils.crypto.aesEncrypt('test', 'aes-128-ecb', '0123456789abcdef');
        const hex = lx.utils.buffer.bufToString(encrypted, 'hex');
        return 'https://cdn.example/?'+new URLSearchParams({base64,digest,hex});
      }); lx.send('inited',{sources:{wy:{qualitys:['128k']}}});
    `, async (page, messages) => {
      await tick(page, messages, () => messages.some(m => m.kind === 'ready'));
      await page.evaluate(() => MestingLxHost.resolve({ songmid: '7' }, '128k'));
      await tick(page, messages, () => messages.some(m => m.kind === 'resolved'));
      const parameters = new URL(messages.find(m => m.kind === 'resolved').url).searchParams;
      assert.equal(parameters.get('digest'), '900150983cd24fb0d6963f7d28e17f72');
      assert.equal(parameters.get('base64'), Buffer.from('音乐').toString('base64'));
      const cipher = require('node:crypto').createCipheriv('aes-128-ecb', Buffer.from('0123456789abcdef'), null);
      const hex = Buffer.concat([cipher.update('test'), cipher.final()]).toString('hex');
      assert.equal(parameters.get('hex'), hex);
    });
    await run('synchronous loop remains terminable', 'while(true){}', async (page) => {
      await page.waitForTimeout(150);
      const started = Date.now();
      assert.equal(await page.evaluate(() => { MestingLxHost.dispose(); return 'responsive'; }), 'responsive');
      assert(Date.now() - started < 1500);
    });
    await run('CSP rejects direct worker fetch', `
      lx.on('request', async () => { try { await fetch('https://example.com/private');return 'bad'; }
        catch (_) { return 'https://cdn.example/csp-blocked'; } });
      lx.send('inited',{sources:{wy:{qualitys:['128k']}}});
    `, async (page, messages) => {
      await tick(page, messages, () => messages.some(m => m.kind === 'ready'));
      await page.evaluate(() => MestingLxHost.resolve({songmid:'7'}, '128k'));
      await tick(page, messages, () => messages.some(m => m.kind === 'resolved'));
      assert.equal(messages.find(m => m.kind === 'resolved').url, 'https://cdn.example/csp-blocked');
    });
    await run('dispose cancels script timers', `
      lx.send('inited',{sources:{wy:{qualitys:['128k']}}});
      setTimeout(()=>lx.request('https://example.com/late',{},()=>{}),200);
    `, async (page, messages) => {
      await tick(page, messages, () => messages.some(m => m.kind === 'ready'));
      await page.evaluate(() => MestingLxHost.dispose());
      await page.waitForTimeout(300);
      assert.equal(messages.filter(m => m.kind === 'request').length, 0);
    });
    if (output) {
      fs.mkdirSync(output, { recursive: true });
      fs.writeFileSync(path.join(output, 'browser-protocol-verification.json'), JSON.stringify({
        tests: reports.length, passed: reports.length, browserOnly: true, nativeAndroidExecuted: false,
        realNetwork: false, phoneAccess: false, accountAccess: false, reports,
      }, null, 2));
    }
  } finally { await browser.close(); }
})().catch(error => { process.stderr.write(`${error.stack}\n`); process.exitCode = 1; });
