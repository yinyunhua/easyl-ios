/**
 * 浏览器扩展 content.js 专用行为测试（不含 iOS 外壳播放器诉求）。
 *
 * 用法：node scripts/test_browser_ext.js browser_ext/content.js
 * 覆盖：
 *   1) 去广告：icons/banners 清空、外链推广数组启发式清空、内链数组不误清
 *   2) VIP 解锁：拦 /app/play/<id>（can_play:false）→ 按 /app/dramas/<id>/episodes + /app/play/<免费集>
 *      推断 storage 基号，改写为 /storage/<base+ep-1>/index.m3u8 并把 is_vip/need_vip 伪造
 *   3) seek 后自动续播（浏览器同样有 WebKit/Blink 的 seek 暂停问题）
 *   4) 不劫持页面布局：__HG_PLAYER_EXTRA__/__HG_PLAYER_TUNE__ 为 false 时不得隐藏任何导航
 */
const fs = require('fs');
const vm = require('vm');

const file = process.argv[2] || 'browser_ext/content.js';
const source = fs.readFileSync(file, 'utf8');

const API = 'https://hgxml.00api-agy5u.com/api';
const CDN = 'https://cdn.example.com';
const docListeners = {};

function jsonResponse(payload) {
  return {
    status: 200,
    statusText: 'OK',
    headers: { get: (k) => (String(k).toLowerCase() === 'content-type' ? 'application/json; charset=utf-8' : null) },
    json: async () => JSON.parse(JSON.stringify(payload)),
    clone() { return jsonResponse(payload); },
    text: async () => JSON.stringify(payload),
  };
}

function makeSandbox(routes) {
  const nodes = [];
  const makeEl = (tag, opts = {}) => {
    const el = {
      tagName: String(tag).toUpperCase(), style: {}, children: [], parentNode: null, id: '',
      innerText: opts.text || '', textContent: opts.text || '',
      classList: { _s: new Set(), add(c) { this._s.add(c); }, remove(c) { this._s.delete(c); }, contains(c) { return this._s.has(c); } },
      getBoundingClientRect: () => opts.rect || { top: 0, left: 0, width: 390, height: 90, bottom: 90, right: 390 },
      setAttribute() {}, getAttribute: () => '',
      appendChild(c) { this.children.push(c); c.parentNode = this; return c; },
      removeChild(c) { const i = this.children.indexOf(c); if (i >= 0) this.children.splice(i, 1); c.parentNode = null; return c; },
      contains: () => false, querySelector: () => null, querySelectorAll: () => [], addEventListener() {},
    };
    nodes.push(el);
    return el;
  };

  const header = makeEl('div', { text: '黄果漫剧 搜索' });
  const dock = makeEl('div', { text: '首页 分类 搜索 我的', rect: { top: 760, left: 0, width: 390, height: 84, bottom: 844, right: 390 } });

  const sandbox = {
    JSON, Math, Promise, Object, Array, String, Number, Boolean, RegExp, Error, isNaN, parseInt, parseFloat, Date, Set, Map,
    console: { log: () => {}, warn: () => {}, error: () => {} },
    setTimeout: (fn) => { try { fn(); } catch (e) {} return 0; },
    setInterval: () => 0, clearInterval: () => {},
    Response: function (body, opts) {
      this.body = body;
      this.status = 200;
      this.statusText = 'OK';
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
      this.clone = () => new Response(body, opts);   // 真实 Response 带 clone，桩也要有（v2 靠它读取响应体）
    },
    XMLHttpRequest: function () { this.open = () => {}; this.send = () => {}; },
    MutationObserver: function () { this.observe = () => {}; },
    getComputedStyle: () => ({ position: 'static', display: 'block', visibility: 'visible', opacity: '1', boxSizing: 'border-box' }),
    innerWidth: 390, innerHeight: 844,
    document: {
      documentElement: makeEl('html'), head: makeEl('head'), body: makeEl('body'),
      createElement: (t) => makeEl(t), getElementById: () => null, querySelectorAll: () => [],
      addEventListener: (t, fn) => { (docListeners[t] = docListeners[t] || []).push(fn); }, removeEventListener: () => {},
    },
    location: { host: 'hgxml.00api-agy5u.com', pathname: '/', href: API + '/' },
    navigator: { userAgent: 'browser-test' },
    addEventListener() {}, removeEventListener() {},
    fetch: async (input) => {
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      const hit = routes.find((r) => url.indexOf(r.match) >= 0);
      return jsonResponse(hit ? hit.body : {});
    },
    __header: header,
    __dock: dock,
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.self = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: file, timeout: 10000 });
  return sandbox;
}

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log(`[${ok ? 'OK' : 'FAIL'}] ${name}${detail ? ' — ' + detail : ''}`);
}

async function run() {
  // ---------- 1) 去广告 ----------
  const adPayload = {
    icons: [{ icon: 'a.png', url: 'https://ad1.example.com/x' }, { icon: 'b.png', url: 'https://ad2.example.com/x' },
            { icon: 'c.png', url: 'https://ad3.example.com/x' }, { icon: 'd.png', url: 'https://ad4.example.com/x' }],
    nav: [{ logo: 'n.png', jump_url: 'https://p1.example.net/a' }, { logo: 'n.png', jump_url: 'https://p2.example.net/a' },
          { logo: 'n.png', jump_url: 'https://p3.example.net/a' }, { logo: 'n.png', jump_url: 'https://p4.example.net/a' }],
    data: { list: [{ id: 1, title: '剧', cover: API + '/c.jpg' }] },
  };
  const s1 = makeSandbox([{ match: '/app/home', body: adPayload }]);
  const home = JSON.parse((await s1.fetch(API + '/app/home')).body);
  check('首页 icons 广告位清空', home.icons.length === 0, `icons=${home.icons.length}`);
  check('外链推广数组（nav）清空', home.nav.length === 0, `nav=${home.nav.length}`);
  check('正常剧目列表保留', home.data.list.length === 1);

  const safePayload = { nav: [{ logo: 'n.png', url: API + '/app/x/1' }, { logo: 'n.png', url: API + '/app/x/2' },
                              { logo: 'n.png', url: API + '/app/x/3' }, { logo: 'n.png', url: API + '/app/x/4' }] };
  const s2 = makeSandbox([{ match: '/app/home', body: safePayload }]);
  const safeHome = JSON.parse((await s2.fetch(API + '/app/home')).body);
  check('内链 nav 不被误清', safeHome.nav.length === 4, `nav=${safeHome.nav.length}`);

  // ---------- 2) VIP 解锁链路 ----------
  const routes = [
    { match: '/app/dramas/123/episodes', body: { list: [{ id: 555, need_vip: false, ep: 1 }] } },
    { match: '/app/play/555', body: { play_url: CDN + '/storage/1000/index.m3u8', can_play: true, is_vip: false } },
    { match: '/app/play/777', body: { can_play: false, ep: 3, drama_id: 123, is_vip: false, need_vip: true, free_episodes: 2 } },
  ];
  const s3 = makeSandbox(routes);
  const play = JSON.parse((await s3.fetch(API + '/app/play/777')).body);
  check('被锁集数解锁（can_play）', play.can_play === true, `can_play=${play.can_play}`);
  check('播放地址改写为 storage 直链（base+ep-1）',
    play.play_url === CDN + '/storage/1002/index.m3u8', String(play.play_url));
  check('伪造会员字段', play.is_vip === true && play.need_vip === false, `is_vip=${play.is_vip} need_vip=${play.need_vip}`);

  const s4 = makeSandbox([{ match: '/app/me', body: { is_vip: false, vip_expire_at: null, free_episodes: 2, user: { is_vip: false, need_vip: true } } }]);
  const me = JSON.parse((await s4.fetch(API + '/app/me')).body);
  check('会员信息接口伪装成 VIP', me.is_vip === true && me.vip_expire_at === '2099-12-31T23:59:59+08:00' && me.free_episodes === 999999,
    `is_vip=${me.is_vip} expire=${me.vip_expire_at} free=${me.free_episodes}`);
  check('嵌套 user 对象同样伪装', me.user.is_vip === true && me.user.need_vip === false);

  // ---------- 3) seek 续播 ----------
  const s5 = makeSandbox([]);
  const v = { tagName: 'VIDEO', paused: false, playCalls: 0 };
  v.play = () => { v.playCalls += 1; v.paused = false; return Promise.resolve(); };
  (docListeners['pause'] || []).forEach((fn) => fn({ target: v }));
  v.paused = true;
  (docListeners['seeking'] || []).forEach((fn) => fn({ target: v }));
  (docListeners['seeked'] || []).forEach((fn) => fn({ target: v }));
  check('seek 后自动续播', v.paused === false && v.playCalls > 0, `playCalls=${v.playCalls}`);

  // ---------- 4) 不劫持布局 ----------
  s5.HGApp.setPlayerMode(true);
  check('浏览器模式不隐藏页面导航（不劫持布局）',
    !s5.__header.classList.contains('hg-immersive-hidden') && !s5.__dock.classList.contains('hg-immersive-hidden'),
    `header=${s5.__header.classList.contains('hg-immersive-hidden')} dock=${s5.__dock.classList.contains('hg-immersive-hidden')}`);

  const failed = results.filter((r) => !r.ok);
  console.log(`\n共 ${results.length} 项，失败 ${failed.length} 项`);
  process.exit(failed.length ? 1 : 0);
}

run().catch((e) => { console.error('测试异常:', e && e.message); process.exit(2); });
