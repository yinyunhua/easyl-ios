/**
 * iOS 增强补丁（__HG_PATCH_V2__）行为测试：在 Node 里给最小 DOM/网络桩，跑真实注入脚本。
 *
 * 用法：node scripts/test_ios_patch.js _analysis/jscheck/ios_patch.js
 * 覆盖：
 *   1) SAFE_KEYS（icons 等）整体清空
 *   2) 外链推广数组按启发式清空（≥4 项且 ≥50% 命中）
 *   3) 自有域名的正常列表保持不变
 *   4) seek 引发的暂停 → 自动续播；用户早于 seek 的主动暂停 → 不误恢复
 *   5) 事件监听注册齐全（pause/seeking/seeked/waiting）
 */
const fs = require('fs');
const vm = require('vm');

const sourcePath = process.argv[2];
if (!sourcePath) {
  console.error('用法: node test_ios_patch.js <ios_patch.js>');
  process.exit(2);
}
const source = fs.readFileSync(sourcePath, 'utf8');

let fakeNow = 1_000_000;
const listeners = {};
const playCalls = [];

function makeResponse(payload, contentType = 'application/json; charset=utf-8') {
  const clonePayload = () => JSON.parse(JSON.stringify(payload));
  return {
    status: 200,
    statusText: 'OK',
    headers: { get: (k) => (String(k).toLowerCase() === 'content-type' ? contentType : null) },
    json: async () => clonePayload(),
    clone: () => makeResponse(payload, contentType),
    text: async () => JSON.stringify(payload),
  };
}

function makeSandbox(nextPayload) {
  const sandbox = {
    JSON, Math, Promise, Object, Array, String, Number, Boolean, RegExp, Error, isNaN, parseInt,
    console: { log: () => {}, warn: () => {}, error: () => {} },
    setTimeout: (fn) => { try { fn(); } catch (e) {} return 0; },
    setInterval: () => 0,
    clearInterval: () => {},
    Date: { now: () => fakeNow },
    Response: function (body, opts) {
      this.body = body;
      this.status = (opts && opts.status) || 200;
      this.statusText = (opts && opts.statusText) || 'OK';
      this.headers = (opts && opts.headers) || {};
      this.json = async () => JSON.parse(body);
    },
    XMLHttpRequest: function () { this.open = () => {}; this.send = () => {}; },
    MutationObserver: function () { this.observe = () => {}; },
    document: {
      documentElement: {},
      addEventListener: (type, fn) => { (listeners[type] = listeners[type] || []).push(fn); },
      querySelectorAll: () => [],
      getElementById: () => null,
      createElement: () => ({ style: {} }),
      head: { appendChild: () => {} },
    },
    location: { host: 'hgxml.00api-agy5u.com', pathname: '/', href: 'https://hgxml.00api-agy5u.com/' },
    navigator: { userAgent: 'node-test' },
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.fetch = async () => makeResponse(nextPayload);
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  return sandbox;
}

function fire(type, target) {
  (listeners[type] || []).forEach((fn) => fn({ target }));
}

function makeVideo() {
  const v = { tagName: 'VIDEO', paused: false, playCalls: 0 };
  v.play = () => { v.playCalls += 1; playCalls.push(v.playCalls); v.paused = false; return Promise.resolve(); };
  return v;
}

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log(`[${ok ? 'OK' : 'FAIL'}] ${name}${detail ? ' — ' + detail : ''}`);
}

async function run() {
  // ---------- 场景 1：混合 payload ----------
  const payload = {
    icons: Array.from({ length: 10 }, (_, i) => ({ icon: `a${i}.png`, url: `https://ad${i}.example.com/app` })),
    nav: Array.from({ length: 5 }, (_, i) => ({ logo: `n${i}.png`, jump_url: `https://promo${i}.example.net/x` })),
    banners: [{ img: 'b.png', link: 'https://banner.example.org' }],
    data: {
      list: Array.from({ length: 6 }, (_, i) => ({ id: i, title: `剧${i}`, cover: `https://hgxml.00api-agy5u.com/c${i}.jpg`, play_url: `https://hgxml.00api-agy5u.com/app/play/${i}` })),
    },
    switches: { ad_enabled: true },
  };
  const sandbox = makeSandbox(payload);
  const res = await sandbox.fetch('https://hgxml.00api-agy5u.com/api/app/home', {});
  const out = JSON.parse(res.body);

  check('icons 被整体清空', Array.isArray(out.icons) && out.icons.length === 0, `icons.length=${out.icons && out.icons.length}`);
  check('banners 被整体清空', Array.isArray(out.banners) && out.banners.length === 0, `banners.length=${out.banners && out.banners.length}`);
  check('nav（外链推广数组，启发式）被清空', Array.isArray(out.nav) && out.nav.length === 0, `nav.length=${out.nav && out.nav.length}`);
  check('合法剧目列表保持不变', Array.isArray(out.data.list) && out.data.list.length === 6, `list.length=${out.data.list && out.data.list.length}`);

  // ---------- 场景 2：全内链的 nav 不应被误清 ----------
  const safePayload = { nav: Array.from({ length: 5 }, (_, i) => ({ logo: `n${i}.png`, url: `https://hgxml.00api-agy5u.com/app/x/${i}` })) };
  const sandbox2 = makeSandbox(safePayload);
  const res2 = await sandbox2.fetch('https://hgxml.00api-agy5u.com/api/app/home', {});
  const out2 = JSON.parse(res2.body);
  check('内链 nav 不被误清', Array.isArray(out2.nav) && out2.nav.length === 5, `nav.length=${out2.nav && out2.nav.length}`);

  // ---------- 场景 3：seek 引发的暂停 → 自动续播 ----------
  check('已注册 pause/seeking/seeked/waiting 监听',
    ['pause', 'seeking', 'seeked', 'waiting'].every((t) => (listeners[t] || []).length > 0),
    Object.keys(listeners).join(','));

  const video = makeVideo();
  fire('pause', video);            // WebKit 在 seek 时的暂停
  video.paused = true;
  fire('seeking', video);
  fire('seeked', video);           // 应立即恢复
  check('seek 后自动续播', video.paused === false && video.playCalls > 0, `playCalls=${video.playCalls} paused=${video.paused}`);

  // ---------- 场景 4：用户早于 seek 的主动暂停 → 不误恢复 ----------
  const video2 = makeVideo();
  fire('pause', video2);           // 用户点暂停
  video2.paused = true;
  fakeNow += 5000;                 // 5 秒后才拖动进度条
  fire('seeking', video2);
  fire('seeked', video2);
  check('用户主动暂停不被误恢复', video2.paused === true && video2.playCalls === 0, `playCalls=${video2.playCalls} paused=${video2.paused}`);

  const failed = results.filter((r) => !r.ok);
  console.log(`\n共 ${results.length} 项，失败 ${failed.length} 项`);
  process.exit(failed.length ? 1 : 0);
}

run().catch((e) => { console.error('测试异常:', e); process.exit(2); });
