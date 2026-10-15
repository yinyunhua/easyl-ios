/**
 * iOS 增强补丁（__HG_PATCH_V2__）行为测试：Node 里搭最小 DOM/网络桩，跑真实注入脚本。
 *
 * 用法：node scripts/test_ios_patch.js _analysis/jscheck/ios_patch.js
 * 覆盖：
 *   1) 广告：SAFE_KEYS 清空 / 外链推广数组启发式清空 / 内链数组不误清
 *   2) 播放：seek 后自动续播；用户早于 seek 的主动暂停不误恢复
 *   3) 播放页：隐藏顶栏与底部 4 tab；含 video 的外层容器绝不隐藏（黑屏回归防护）
 *   4) 沉浸式：fixed 播放层不动定位；视频铺满；退还原样
 *   5) 竖屏调优：控件行钉常显 / 选集条贴底并为它预留高度 / 速度键左移并回传坐标 / 视频满宽渲染 / 居中不抖动
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
const bridgeMessages = [];
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
  getBoundingClientRect() {
    const n = typeof this.__hgNudge === 'number' ? this.__hgNudge : 0;
    const r = this._rect;
    return { top: r.top + n, bottom: r.bottom + n, left: r.left, right: r.right, width: r.width, height: r.height };
  }
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
    const hit = matchAll(this, s);
    return hit.length ? hit[0] : null;
  }
  querySelectorAll(sel) { return matchAll(this, sel); }
  addEventListener() {}
}

function matchesTag(el, sel) {
  const s = String(sel).trim();
  if (!s) return false;
  if (s === 'video') return el.tagName === 'VIDEO';
  if (s === 'a[href]') return el.tagName === 'A' && !!el.getAttribute('href');
  if (s.indexOf('.hg-player-box') >= 0) return el._classes.has('hg-player-box');
  if (s.indexOf('.hg-fill-video') >= 0) return el._classes.has('hg-fill-video');
  const tags = s.split(',').map((t) => t.trim().toUpperCase()).filter(Boolean);
  return tags.includes(el.tagName);
}

function matchAll(root, sel) {
  const out = [];
  const walk = (node) => {
    node.children.forEach((child) => {
      if (matchesTag(child, sel)) out.push(child);
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

  // 回归场景：外层容器「含 video」且「底部带 4 个主 tab 文案」——绝不能被隐藏
  const pageWrapper = new El('div', {
    text: '选集 连载 在线观看 首页 分类 搜索 我的',
    hasVideo: true,
    rect: { top: 130, left: 0, width: VW, height: VH - 130, bottom: VH, right: VW },
  });
  const box = new El('div', {
    hasVideo: true,
    position: 'fixed',
    rect: { top: 150, left: 0, width: VW, height: 600, bottom: 750, right: VW },
  });
  const video = new El('video', { rect: { top: 300, left: 0, width: VW, height: 220, bottom: 520, right: VW } });
  // H5 控件行：含时间文本，位于下半屏
  const controls = new El('div', {
    text: '骨肉亲 1.0x 0:48 4:23',
    rect: { top: 660, left: 0, width: VW, height: 70, bottom: 730, right: VW },
  });
  const speed = new El('span', { text: '1.0x', rect: { top: 660, left: 320, width: 40, height: 24, bottom: 684, right: 360 } });
  controls.appendChild(speed);
  box.appendChild(video);
  box.appendChild(controls);
  pageWrapper.appendChild(box);
  pageWrapper.__videoRef = video;
  box.__videoRef = video;

  // 选集条：贴在播放区下方
  const strip = new El('div', {
    text: '选集 · 更新至第8集 · 在线观看',
    rect: { top: 750, left: 0, width: VW, height: 56, bottom: 806, right: VW },
  });

  const dock = new El('div', {
    text: '首页 分类 搜索 我的',
    rect: { top: VH - 80, left: 0, width: VW, height: 80, bottom: VH, right: VW },
  });

  body.appendChild(header);
  body.appendChild(pageWrapper);
  body.appendChild(strip);
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
  return { document, header, dock, pageWrapper, box, video, controls, speed, strip, registry };
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
      var rawHeaders = (opts && opts.headers) || {};
      this.headers = {
        // 真实 Response.headers 一定有 get()；桩要是丢了它，v2 读 content-type 会拿到空值而静默跳过
        get: function (name) {
          var key = String(name).toLowerCase();
          for (var p in rawHeaders) { if (String(p).toLowerCase() === key) { return rawHeaders[p]; } }
          return null;
        },
      };
      this.json = async () => JSON.parse(body);
      this.text = async () => String(body);
      this.clone = () => new Response(body, opts);   // 真实 Response 有 clone，桩也要有（v2 依赖它读取响应体）
    },
    XMLHttpRequest: function () { this.open = () => {}; this.send = () => {}; },
    MutationObserver: function () { this.observe = () => {}; },
    getComputedStyle: (el) => ({
      position: (el && el._position) || 'static',
      display: 'block',
      visibility: 'visible',
      opacity: '1',
      boxSizing: 'border-box',
    }),
    document: dom.document,
    innerWidth: VW,
    innerHeight: VH,
    location: { host: 'hgxml.00api-agy5u.com', pathname: '/', href: 'https://hgxml.00api-agy5u.com/' },
    navigator: { userAgent: 'node-test' },
    addEventListener: () => {},
    removeEventListener: () => {},
    webkit: { messageHandlers: { HuangGuoNative: { postMessage: (body) => bridgeMessages.push(body) } } },
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

  // ---------- 播放页 + 调优 ----------
  const { sandbox: s, dom } = makeSandbox({});
  check('暴露播放页 API', typeof s.HGApp.setPlayerMode === 'function'
    && typeof s.HGApp.setImmersive === 'function'
    && typeof s.HGApp.centerVideo === 'function'
    && typeof s.HGApp.layoutPlayer === 'function', 'setPlayerMode/setImmersive/centerVideo/layoutPlayer');

  s.HGApp.setPlayerMode(true);
  s.HGApp.layoutPlayer(true);

  check('顶栏（logo+搜索）被隐藏', dom.header._classes.has('hg-immersive-hidden'));
  check('底部 4 tab 被隐藏', dom.dock._classes.has('hg-immersive-hidden'));
  check('★含 video 的外层容器未被隐藏（黑屏回归防护）', !dom.pageWrapper._classes.has('hg-immersive-hidden'));
  check('★隐藏导航后未触发回滚', s.HGApp.__lastRollback === undefined, String(s.HGApp.__lastRollback || '无回滚'));

  check('控件行被钉住常显（进度条不再自动消失）', dom.controls._classes.has('hg-controls-pinned'), dom.controls._classes.has('hg-controls-pinned') ? '已钉' : '未钉');
  check('选集条默认隐藏（不再遮挡画面）', dom.strip._classes.has('hg-strip-hidden'), dom.strip._classes.has('hg-strip-hidden') ? '已隐藏' : '未隐藏');
  s.HGApp.setStripHidden(false);
  check('恢复选集条：贴底 + 预留高度（控件上移不遮挡）',
    dom.strip._classes.has('hg-strip-bottom') && dom.box.style.paddingBottom === '60px',
    `bottom=${dom.strip._classes.has('hg-strip-bottom')} pad=${dom.box.style.paddingBottom}`);
  s.HGApp.setStripHidden(true);
  check('再次隐藏选集条', dom.strip._classes.has('hg-strip-hidden'));
  check('速度键左移', dom.speed._classes.has('hg-speed-shifted'));
  check('竖屏视频满宽渲染（清晰度）', dom.video._classes.has('hg-fill-video'));
  check('回传速度键坐标给原生（原生全屏键贴其右侧）',
    bridgeMessages.some((m) => String(m).indexOf('playerControls') >= 0), String(bridgeMessages[bridgeMessages.length - 1] || '无'));

  const info = JSON.parse(String(s.HGApp.videoInfo()));
  check('上报视频比例（用于自动横竖屏）', info.w > 0 && info.h > 0, JSON.stringify(info));
  bridgeMessages.length = 0;
  fire('webkitbeginfullscreen', null);
  check('进入全屏时上报 fullscreenState=1',
    bridgeMessages.some((m) => String(m).indexOf('fullscreenState') >= 0 && String(m).indexOf('"args":[1') >= 0),
    String(bridgeMessages[bridgeMessages.length - 1] || '无'));
  bridgeMessages.length = 0;
  fire('webkitendfullscreen', null);
  check('退出全屏时上报 fullscreenState=0',
    bridgeMessages.some((m) => String(m).indexOf('fullscreenState') >= 0 && String(m).indexOf('"args":[0') >= 0),
    String(bridgeMessages[bridgeMessages.length - 1] || '无'));

  // 抖动修复：同尺寸下重复 layoutPlayer 不应重写 transform
  const t1 = String(dom.video.style.transform || '');
  s.HGApp.layoutPlayer(true);
  const t2 = String(dom.video.style.transform || '');
  check('★居中不抖动（重复布局不重写 transform）', t1 === t2, `t1=${JSON.stringify(t1)} t2=${JSON.stringify(t2)}`);
  const t3 = s.HGApp.centerVideo();
  check('★居中带 keep 短路', /keep=|dy=/.test(String(t3)), String(t3));

  // ---------- 沉浸式仍安全 ----------
  s.HGApp.setImmersive(true);
  check('横屏沉浸式：html 标记', dom.document.documentElement._classes.has('hg-immersive'));
  check('★fixed 播放层不被强改定位撑高（黑屏回归防护）', !dom.box._classes.has('hg-player-box'));
  check('沉浸式未触发回滚', s.HGApp.__lastRollback === undefined, String(s.HGApp.__lastRollback || '无回滚'));

  s.HGApp.setImmersive(false);
  s.HGApp.setPlayerMode(false);
  check('退出播放页：导航恢复', !dom.header._classes.has('hg-immersive-hidden') && !dom.dock._classes.has('hg-immersive-hidden'));

  const failed = results.filter((r) => !r.ok);
  console.log(`\n共 ${results.length} 项，失败 ${failed.length} 项`);
  process.exit(failed.length ? 1 : 0);
}

run().catch((e) => { console.error('测试异常:', e); process.exit(2); });
