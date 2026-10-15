/**
 * iOS 增强补丁（__HG_PATCH_V2__）行为测试：Node 里搭最小 DOM/网络桩，跑真实注入脚本。
 *
 * 用法：node scripts/test_ios_patch.js _analysis/jscheck/ios_patch.js
 * 覆盖：
 *   1) 广告：SAFE_KEYS 清空 / 外链推广数组启发式清空 / 内链数组不误清
 *   2) 播放：seek 后自动续播；用户早于 seek 的主动暂停不误恢复
 *   3) 播放页：隐藏顶栏（logo+搜索）与底部 4 tab；**含 video 的外层容器绝不能被隐藏**（黑屏回归防护）
 *   4) 沉浸式：只给文档流内容器撑高（fixed 播放层不动）；视频铺满；居中带幅度上限；退出干净还原
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
const VH = 844;
const VW = 390;

class El {
  constructor(tag, opts = {}) {
    this.tagName = String(tag).toUpperCase();
    this.style = {};
    this.children = [];
    this.parentNode = null;
    this.innerText = opts.text || '';
    this.textContent = opts.text || '';
    this.id = opts.id || '';
    this._rect = opts.rect || { top: 0, left: 0, width: 0, height: 0, bottom: 0, right: 0 };
    this._classes = new Set(opts.classes || []);
    this._hasVideo = !!opts.hasVideo;
    this._position = opts.position || 'static';
    this.hasSearchInput = !!opts.hasSearchInput;
    const self = this;
    this.classList = {
      add: (c) => self._classes.add(c),
      remove: (c) => self._classes.delete(c),
      contains: (c) => self._classes.has(c),
    };
    this.attrs = {};
  }
  getBoundingClientRect() { return this._rect; }
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
    const s = String(sel);
    if (s === 'video') return this._hasVideo ? (this.__videoRef || true) : null;
    if (this.hasSearchInput && s.indexOf('input') >= 0) return new El('input');
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

  const header = new El('div', {
    text: '黄果漫剧 搜索',
    hasSearchInput: true,
    rect: { top: 40, left: 0, width: VW, height: 90, bottom: 130, right: VW },
  });

  // 关键回归场景：外层容器同时「含 video」且「底部带 4 个主 tab 文案」——绝不能被隐藏
  const pageWrapper = new El('div', {
    text: '选集 连载 在线观看 首页 分类 搜索 我的',
    hasVideo: true,
    rect: { top: 130, left: 0, width: VW, height: VH - 130, bottom: VH, right: VW },
  });
  const box = new El('div', {
    hasVideo: true,
    position: 'fixed',
    rect: { top: 130, left: 0, width: VW, height: VH - 230, bottom: VH - 100, right: VW },
  });
  const video = new El('video', { rect: { top: 300, left: 0, width: VW, height: 220, bottom: 520, right: VW } });
  box.appendChild(video);
  pageWrapper.appendChild(box);
  pageWrapper.__videoRef = video;
  box.__videoRef = video;

  const dock = new El('div', {
    text: '首页 分类 搜索 我的',
    rect: { top: VH - 80, left: 0, width: VW, height: 80, bottom: VH, right: VW },
  });

  body.appendChild(header);
  body.appendChild(pageWrapper);
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
  head.appendChild = (child) => { if (child.id) registry[child.id] = child; origAppend(child); child.parentNode = head; return child; };
  return { document, header, dock, pageWrapper, box, video, registry };
}

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
    JSON, Math, Promise, Object, Array, String, Number, Boolean, RegExp, Error, isNaN, parseInt, parseFloat,
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
    getComputedStyle: (el) => ({
      position: (el && el._position) || 'static',
      display: 'block',
      visibility: 'visible',
      opacity: '1',
    }),
    document: dom.document,
    innerWidth: VW,
    innerHeight: VH,
    location: { host: 'hgxml.00api-agy5u.com', pathname: '/', href: 'https://hgxml.00api-agy5u.com/' },
    navigator: { userAgent: 'node-test' },
    addEventListener: () => {},
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
  // ---------- 广告 ----------
  const payload = {
    icons: Array.from({ length: 10 }, (_, i) => ({ icon: `a${i}.png`, url: `https://ad${i}.example.com/app` })),
    nav: Array.from({ length: 5 }, (_, i) => ({ logo: `n${i}.png`, jump_url: `https://promo${i}.example.net/x` })),
    banners: [{ img: 'b.png', link: 'https://banner.example.org' }],
    data: { list: Array.from({ length: 6 }, (_, i) => ({ id: i, title: `剧${i}`, cover: `https://hgxml.00api-agy5u.com/c${i}.jpg` })) },
  };
  const { sandbox } = makeSandbox(payload);
  const out = JSON.parse((await sandbox.fetch('https://hgxml.00api-agy5u.com/api/app/home', {})).body);
  check('icons 被整体清空', out.icons.length === 0, `icons=${out.icons.length}`);
  check('banners 被整体清空', out.banners.length === 0, `banners=${out.banners.length}`);
  check('nav（外链推广数组）被清空', out.nav.length === 0, `nav=${out.nav.length}`);
  check('合法剧目列表保持不变', out.data.list.length === 6, `list=${out.data.list.length}`);

  const safePayload = { nav: Array.from({ length: 5 }, (_, i) => ({ logo: `n${i}.png`, url: `https://hgxml.00api-agy5u.com/app/x/${i}` })) };
  const { sandbox: sandboxSafe } = makeSandbox(safePayload);
  const outSafe = JSON.parse((await sandboxSafe.fetch('https://hgxml.00api-agy5u.com/api/app/home', {})).body);
  check('内链 nav 不被误清', outSafe.nav.length === 5, `nav=${outSafe.nav.length}`);

  // ---------- seek ----------
  check('注册 seek 相关监听', ['pause', 'seeking', 'seeked', 'waiting'].every((t) => (docListeners[t] || []).length > 0));
  const videoA = makeVideo();
  fire('pause', videoA);
  videoA.paused = true;
  fire('seeking', videoA);
  fire('seeked', videoA);
  check('seek 后自动续播', videoA.paused === false && videoA.playCalls > 0, `playCalls=${videoA.playCalls}`);

  const videoB = makeVideo();
  fire('pause', videoB);
  videoB.paused = true;
  fakeNow += 5000;
  fire('seeking', videoB);
  fire('seeked', videoB);
  check('用户主动暂停不被误恢复', videoB.paused === true && videoB.playCalls === 0, `playCalls=${videoB.playCalls}`);

  // ---------- 播放页：隐藏导航（含黑屏回归防护） ----------
  const { sandbox: s, dom } = makeSandbox({});
  check('暴露播放页 API', typeof s.HGApp.setPlayerMode === 'function'
    && typeof s.HGApp.setImmersive === 'function'
    && typeof s.HGApp.centerVideo === 'function', 'setPlayerMode/setImmersive/centerVideo');

  s.HGApp.setPlayerMode(true);
  check('顶栏（logo+搜索）被隐藏', dom.header._classes.has('hg-immersive-hidden'));
  check('底部 4 tab 被隐藏', dom.dock._classes.has('hg-immersive-hidden'));
  check('★含 video 的外层容器未被隐藏（黑屏回归防护）', !dom.pageWrapper._classes.has('hg-immersive-hidden'),
    '隐藏类: ' + (dom.pageWrapper._classes.has('hg-immersive-hidden') ? '有' : '无'));
  check('★隐藏导航后未触发回滚', s.HGApp.__lastRollback === undefined, String(s.HGApp.__lastRollback || '无回滚'));
  check('注入沉浸式样式表', dom.registry['hg-immersive-css'] !== null);

  // ---------- 沉浸式 ----------
  s.HGApp.setImmersive(true);
  check('横屏沉浸式：html 标记', dom.document.documentElement._classes.has('hg-immersive'));
  check('★fixed 播放层不被强改定位撑高（黑屏回归防护）', !dom.box._classes.has('hg-player-box'),
    'hg-player-box: ' + (dom.box._classes.has('hg-player-box') ? '有' : '无'));
  check('横屏沉浸式：视频铺满（清晰度）', dom.video._classes.has('hg-fill-video'));
  check('沉浸式未触发回滚', s.HGApp.__lastRollback === undefined, String(s.HGApp.__lastRollback || '无回滚'));

  const centerResult = s.HGApp.centerVideo();
  const dy = /dy=(-?\d+)/.exec(String(centerResult));
  check('居中返回偏移', !!dy, String(centerResult));
  check('居中幅度不超过视口 25%', !dy || Math.abs(parseInt(dy[1], 10)) <= VH * 0.25, String(centerResult));

  s.HGApp.setImmersive(false);
  check('退出沉浸式：取消视频铺满类', !dom.video._classes.has('hg-fill-video'));
  check('退出沉浸式：竖屏仍做居中且非 NaN', !/NaN/.test(String(dom.video.style.transform || '')), String(dom.video.style.transform));

  s.HGApp.setPlayerMode(false);
  check('退出播放页：导航恢复', !dom.header._classes.has('hg-immersive-hidden') && !dom.dock._classes.has('hg-immersive-hidden'));
  check('退出播放页：视频内联样式被还原', !String(dom.video.style.transform || '').trim(), JSON.stringify(String(dom.video.style.transform || '')));

  const failed = results.filter((r) => !r.ok);
  console.log(`\n共 ${results.length} 项，失败 ${failed.length} 项`);
  process.exit(failed.length ? 1 : 0);
}

run().catch((e) => { console.error('测试异常:', e); process.exit(2); });
