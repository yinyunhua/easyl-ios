/**
 * iOS 增强补丁（__HG_PATCH_V2__）行为测试：在 Node 里搭最小 DOM/网络桩，跑真实注入脚本。
 *
 * 用法：node scripts/test_ios_patch.js _analysis/jscheck/ios_patch.js
 * 覆盖：
 *   1) 广告：SAFE_KEYS 清空 / 外链推广数组启发式清空 / 内链数组不误清
 *   2) 播放：seek 后自动续播；用户早于 seek 的主动暂停不误恢复
 *   3) 播放页：隐藏 H5 顶栏（logo+搜索）与底部 4 tab；沉浸式给播放器盒 + 视频铺满类；居中 nudge；退出时干净还原
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
const docListeners = {};
const winListeners = {};

// ---------------- 极简 DOM ----------------
class El {
  constructor(tag, opts = {}) {
    this.tagName = String(tag).toUpperCase();
    this.style = {};
    this.children = [];
    this.parentNode = null;
    this.innerText = opts.text || '';
    this.textContent = opts.text || '';
    this._rect = opts.rect || { top: 0, left: 0, width: 0, height: 0, bottom: 0, right: 0 };
    this._classes = new Set(opts.classes || []);
    const self = this;
    this.classList = {
      add: (c) => self._classes.add(c),
      remove: (c) => self._classes.delete(c),
      contains: (c) => self._classes.has(c),
      toString: () => Array.from(self._classes).join(' '),
    };
    this.attrs = {};
    this.hasSearchInput = !!opts.hasSearchInput;
  }
  getBoundingClientRect() { return this._rect; }
  setBoundingRect(r) { this._rect = r; }
  setAttribute(k, v) { this.attrs[k] = v; }
  getAttribute(k) { return this.attrs[k] === undefined ? '' : this.attrs[k]; }
  appendChild(child) { this.children.push(child); child.parentNode = this; return child; }
  removeChild(child) {
    const i = this.children.indexOf(child);
    if (i >= 0) this.children.splice(i, 1);
    child.parentNode = null;
    return child;
  }
  contains(node) {
    if (node === this) return true;
    return this.children.some((c) => c.contains(node));
  }
  querySelector(sel) {
    if (this.hasSearchInput && String(sel).indexOf('input') >= 0) return new El('input');
    return null;
  }
  querySelectorAll(sel) { return matchAll(this, sel); }
  addEventListener() {}
}

function matchAll(root, sel) {
  sel = String(sel);
  const out = [];
  const walk = (node) => {
    node.children.forEach((child) => {
      let hit = false;
      if (sel === 'video' && child.tagName === 'VIDEO') hit = true;
      else if (sel === 'a[href]' && child.tagName === 'A' && child.getAttribute('href')) hit = true;
      else if (sel.indexOf('.hg-player-box') >= 0 && child._classes.has('hg-player-box')) hit = true;
      else if (sel.indexOf('.hg-fill-video') >= 0 && child._classes.has('hg-fill-video')) hit = true;
      if (hit) out.push(child);
      walk(child);
    });
  };
  walk(root);
  return out;
}

function buildDom() {
  const documentElement = new El('html');
  const head = new El('head');
  const body = new El('body');
  documentElement.appendChild(head);
  documentElement.appendChild(body);

  const header = new El('div', { text: '黄果漫剧 搜索', hasSearchInput: true, rect: { top: 40, left: 0, width: 390, height: 90, bottom: 130, right: 390 } });
  const dock = new El('div', { text: '首页 分类 搜索 我的', rect: { top: 780, left: 0, width: 390, height: 80, bottom: 860, right: 390 } });
  const box = new El('div', { rect: { top: 130, left: 0, width: 390, height: 650, bottom: 780, right: 390 } });
  const video = new El('video', { rect: { top: 300, left: 0, width: 390, height: 220, bottom: 520, right: 390 } });
  box.appendChild(video);
  body.appendChild(header);
  body.appendChild(box);
  body.appendChild(dock);

  const registry = { 'hg-immersive-css': null, 'hg-shell-tap-css': null };
  const document = {
    documentElement, head, body,
    createElement: (t) => new El(t),
    getElementById: (id) => registry[id] || null,
    querySelectorAll: (sel) => matchAll(documentElement, sel),
    addEventListener: (type, fn) => { (docListeners[type] = docListeners[type] || []).push(fn); },
    removeEventListener: () => {},
    fullscreenElement: null,
  };
  const origAppend = head.appendChild.bind(head);
  head.appendChild = (child) => { if (child.attrs && child.id) registry[child.id] = child; else if (child.id) registry[child.id] = child; origAppend(child); child.parentNode = head; return child; };
  return { document, header, dock, box, video, registry };
}

// ---------------- 网络桩 ----------------
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
  const dom = buildDom();
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
    document: dom.document,
    innerWidth: 390,
    innerHeight: 844,
    location: { host: 'hgxml.00api-agy5u.com', pathname: '/', href: 'https://hgxml.00api-agy5u.com/' },
    navigator: { userAgent: 'node-test' },
    addEventListener: (type, fn) => { (winListeners[type] = winListeners[type] || []).push(fn); },
    removeEventListener: () => {},
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.fetch = async () => makeResponse(nextPayload);
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  return { sandbox, dom };
}

function fire(type, target) {
  (docListeners[type] || []).forEach((fn) => fn({ target }));
}

function makeVideo() {
  const v = { tagName: 'VIDEO', paused: false, playCalls: 0 };
  v.play = () => { v.playCalls += 1; v.paused = false; return Promise.resolve(); };
  return v;
}

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log(`[${ok ? 'OK' : 'FAIL'}] ${name}${detail ? ' — ' + detail : ''}`);
}

async function run() {
  // ---------- 广告：混合 payload ----------
  const payload = {
    icons: Array.from({ length: 10 }, (_, i) => ({ icon: `a${i}.png`, url: `https://ad${i}.example.com/app` })),
    nav: Array.from({ length: 5 }, (_, i) => ({ logo: `n${i}.png`, jump_url: `https://promo${i}.example.net/x` })),
    banners: [{ img: 'b.png', link: 'https://banner.example.org' }],
    data: { list: Array.from({ length: 6 }, (_, i) => ({ id: i, title: `剧${i}`, cover: `https://hgxml.00api-agy5u.com/c${i}.jpg` })) },
  };
  const { sandbox } = makeSandbox(payload);
  const res = await sandbox.fetch('https://hgxml.00api-agy5u.com/api/app/home', {});
  const out = JSON.parse(res.body);
  check('icons 被整体清空', out.icons.length === 0, `icons=${out.icons.length}`);
  check('banners 被整体清空', out.banners.length === 0, `banners=${out.banners.length}`);
  check('nav（外链推广数组）被清空', out.nav.length === 0, `nav=${out.nav.length}`);
  check('合法剧目列表保持不变', out.data.list.length === 6, `list=${out.data.list.length}`);

  const safePayload = { nav: Array.from({ length: 5 }, (_, i) => ({ logo: `n${i}.png`, url: `https://hgxml.00api-agy5u.com/app/x/${i}` })) };
  const { sandbox: sandbox2 } = makeSandbox(safePayload);
  const res2 = await sandbox2.fetch('https://hgxml.00api-agy5u.com/api/app/home', {});
  check('内链 nav 不被误清', JSON.parse(res2.body).nav.length === 5, `nav=${JSON.parse(res2.body).nav.length}`);

  // ---------- seek 续播 ----------
  check('注册 seek 相关监听', ['pause', 'seeking', 'seeked', 'waiting'].every((t) => (docListeners[t] || []).length > 0));

  const video = makeVideo();
  fire('pause', video);
  video.paused = true;
  fire('seeking', video);
  fire('seeked', video);
  check('seek 后自动续播', video.paused === false && video.playCalls > 0, `playCalls=${video.playCalls}`);

  const video2 = makeVideo();
  fire('pause', video2);
  video2.paused = true;
  fakeNow += 5000;
  fire('seeking', video2);
  fire('seeked', video2);
  check('用户主动暂停不被误恢复', video2.paused === true && video2.playCalls === 0, `playCalls=${video2.playCalls}`);

  // ---------- 播放页：隐藏导航 + 沉浸式 + 居中 ----------
  const { sandbox: s3, dom } = makeSandbox({});
  check('暴露播放页 API', typeof s3.HGApp.setPlayerMode === 'function'
    && typeof s3.HGApp.setImmersive === 'function'
    && typeof s3.HGApp.centerVideo === 'function', 'setPlayerMode/setImmersive/centerVideo');

  s3.HGApp.setPlayerMode(true);
  check('顶栏（logo+搜索）被隐藏', dom.header._classes.has('hg-immersive-hidden'), dom.header._classes.toString());
  check('底部 4 tab 被隐藏', dom.dock._classes.has('hg-immersive-hidden'), dom.dock._classes.toString());
  check('注入沉浸式样式表', dom.registry['hg-immersive-css'] !== null, 'hg-immersive-css');

  s3.HGApp.setImmersive(true);
  check('横屏沉浸式：html 标记', dom.document.documentElement._classes.has('hg-immersive'));
  check('横屏沉浸式：播放器盒铺满', dom.box._classes.has('hg-player-box'), dom.box._classes.toString());
  check('横屏沉浸式：视频铺满（清晰度）', dom.video._classes.has('hg-fill-video'), dom.video._classes.toString());

  const centerResult = s3.HGApp.centerVideo();
  check('居中计算返回偏移', String(centerResult).indexOf('dy=') === 0, String(centerResult));
  check('居中写回 transform', String(dom.video.style.transform || '').indexOf('translateY') >= 0, String(dom.video.style.transform));

  s3.HGApp.setImmersive(false);
  check('退出沉浸式：还原播放器盒', !dom.box._classes.has('hg-player-box'));
  check('退出沉浸式：取消视频铺满类', !dom.video._classes.has('hg-fill-video'));
  check('退出沉浸式：竖屏仍做居中（有限值，非 NaN）',
    !/NaN/.test(String(dom.video.style.transform || '')), String(dom.video.style.transform));

  s3.HGApp.setPlayerMode(false);
  check('退出播放页：导航恢复', !dom.header._classes.has('hg-immersive-hidden') && !dom.dock._classes.has('hg-immersive-hidden'));
  check('退出播放页：视频内联样式被还原', !String(dom.video.style.transform || '').trim(), JSON.stringify(String(dom.video.style.transform || '')));

  const failed = results.filter((r) => !r.ok);
  console.log(`\n共 ${results.length} 项，失败 ${failed.length} 项`);
  process.exit(failed.length ? 1 : 0);
}

run().catch((e) => { console.error('测试异常:', e); process.exit(2); });
