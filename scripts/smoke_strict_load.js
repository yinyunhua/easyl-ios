/**
 * 严格模式加载冒烟：在 'use strict' 下用最小 DOM 桩把脚本整体求值一次，
 * 任何「未声明标识符」会在加载期直接抛错（普通模式下赋值会静默创建全局，很难发现）。
 *
 * 真实案例：ios_patch 里的 `fsActive` 从未声明 —— WebView 非严格模式下没报错，
 * 但 playerDiag 读它时抛错被 try/catch 吞掉，导致原生看门狗一直拿不到诊断。
 *
 * 用法：node scripts/smoke_strict_load.js <file.js>
 */
const fs = require('fs');
const vm = require('vm');

const file = process.argv[2];
if (!file) {
  console.error('用法: node smoke_strict_load.js <file.js>');
  process.exit(2);
}
const code = "'use strict';\n" + fs.readFileSync(file, 'utf8');

function stubElement(tag) {
  const el = {
    tagName: String(tag).toUpperCase(),
    style: {}, children: [], parentNode: null, id: '', innerText: '', textContent: '',
    classList: { add() {}, remove() {}, contains: () => false },
    getBoundingClientRect: () => ({ top: 0, left: 0, width: 0, height: 0, bottom: 0, right: 0 }),
    setAttribute() {}, getAttribute: () => '',
    appendChild(c) { this.children.push(c); return c; },
    removeChild(c) { return c; },
    contains: () => false,
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener() {}, removeEventListener() {},
  };
  return el;
}

const documentElement = stubElement('html');
const listeners = {};
const sandbox = {
  JSON, Math, Promise, Object, Array, String, Number, Boolean, RegExp, Error, isNaN, parseInt, parseFloat, Date, Set, Map,
  console: { log() {}, warn() {}, error() {} },
  setTimeout: (fn) => { try { fn(); } catch (e) {} return 0; },
  setInterval: () => 0,
  clearInterval: () => {},
  Response: function (body, opts) { this.body = body; this.status = 200; this.statusText = 'OK'; this.headers = (opts && opts.headers) || {}; this.json = async () => JSON.parse(body); },
  XMLHttpRequest: function () { this.open = () => {}; this.send = () => {}; },
  MutationObserver: function () { this.observe = () => {}; },
  getComputedStyle: () => ({ position: 'static', display: 'block', visibility: 'visible', opacity: '1', boxSizing: 'border-box' }),
  innerWidth: 390,
  innerHeight: 844,
  document: {
    documentElement,
    head: stubElement('head'),
    body: stubElement('body'),
    createElement: (t) => stubElement(t),
    getElementById: () => null,
    querySelectorAll: () => [],
    addEventListener: (t, fn) => { (listeners[t] = listeners[t] || []).push(fn); },
    removeEventListener: () => {},
  },
  location: { host: 'localhost', pathname: '/', href: 'http://localhost/' },
  navigator: { userAgent: 'node-smoke' },
  addEventListener() {}, removeEventListener() {},
  fetch: async () => ({ status: 200, headers: { get: () => 'application/json' }, json: async () => ({}) }),
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
sandbox.self = sandbox;

try {
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: file, timeout: 10000 });
} catch (error) {
  console.error(`[FAIL] 严格模式加载抛错：${error && error.message}`);
  process.exit(1);
}

// 触发一遍常见事件处理器，顺带覆盖闭包内未声明标识符
try {
  ['pause', 'seeking', 'seeked', 'waiting', 'webkitbeginfullscreen', 'webkitendfullscreen', 'click', 'touchend', 'resize', 'orientationchange']
    .forEach((type) => (listeners[type] || []).forEach((fn) => fn({ target: stubElement('video') })));
} catch (error) {
  console.error(`[FAIL] 事件回调抛错：${error && error.message}`);
  process.exit(1);
}

console.log(`[OK] 严格模式加载与事件回调均无未声明标识符：${file}`);
