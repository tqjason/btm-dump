#!/usr/bin/env node
/*
 * btm-selftest.js —— 浏览页自检（仅开发用，不参与正常使用）
 *
 * 用最小 DOM 桩在 Node 里真跑一遍 btm_items.html 里的 JS，
 * 覆盖：表格渲染 / 排序 / 筛选 / 列面板 / 8 棵关系树 / 折叠 / 详情面板 / 字段说明 / 视图切换。
 *
 * 用法：
 *   node btm-selftest.js <快照目录>/btm_items.html     # 页面自检（含语言切换复检）
 *   node btm-selftest.js --i18n btm-view.tpl.html      # 只查双语字典：键位一致 + 引用完整
 *
 * 断言一律从当前数据与当前语言的字典推导，不写死任何一种语言的文案。
 * 主体跑页面默认语言（由桩的 navigator 决定 = zh），末尾再切到 en 复检一遍。
 *
 * 注意：这不是工具链的一部分，正常使用 btm.sh 完全不需要 Node。
 */

'use strict';
const fs = require('fs'), vm = require('vm'), path = require('path');

/* ------------------------------------------------------------------
 * --i18n：模板双语字典的一致性检查（不需要快照，直接查模板源文件）
 * ------------------------------------------------------------------ */
if (process.argv[2] === '--i18n') {
  const tpl = process.argv[3] || path.join(__dirname, 'btm-view.tpl.html');
  const src = fs.readFileSync(tpl, 'utf8');
  const m = src.match(/<script>\n([\s\S]*?)\n<\/script>/);
  if (!m) { console.error('✗ 模板里找不到主脚本块：' + tpl); process.exit(1); }
  const js = m[1];

  // 双语字典块整体就是合法 JS（/* ===BTM_I18N_*=== */ 与 /* ---BTM_I18N:xx--- */ 都是注释），
  // 直接整段求值拿到 I18N，不必再按标记切片。
  const i = js.indexOf('/* ===BTM_I18N_BEGIN=== */');
  const j = js.indexOf('/* ===BTM_I18N_END=== */');
  if (i < 0 || j < 0) { console.error('✗ 模板里找不到 BTM_I18N_BEGIN / BTM_I18N_END 标记'); process.exit(1); }
  const box = {};
  vm.createContext(box);
  try { vm.runInContext(js.slice(i, j) + '\n; this.__I = I18N;', box); }
  catch (e) { console.error('✗ 字典块不是合法 JS：' + e.message); process.exit(1); }
  const I = box.__I || {};
  if (!I.zh || !I.zh.l || !I.en || !I.en.l) {
    console.error('✗ 字典块里缺 I18N.zh.l 或 I18N.en.l（页面将无法切换语言）');
    process.exit(1);
  }
  const dicts = { zh: { L: I.zh.l, V: I.zh.v || {} }, en: { L: I.en.l, V: I.en.v || {} } };

  let n = 0;
  const fail = (s) => { n++; console.log('  ✗ ' + s); };
  const kz = Object.keys(dicts.zh.L).sort(), ke = Object.keys(dicts.en.L).sort();
  console.log('字典：zh ' + kz.length + ' 键　en ' + ke.length + ' 键');
  const missEn = kz.filter(k => ke.indexOf(k) < 0), missZh = ke.filter(k => kz.indexOf(k) < 0);
  if (missEn.length) fail('en 缺少这些键：' + missEn.join(', '));
  if (missZh.length) fail('zh 缺少这些键：' + missZh.join(', '));
  if (!missEn.length && !missZh.length) console.log('  ✓ 两份字典键位一一对应');

  // 代码里引用到的键都必须有定义（'x.' 结尾的是动态前缀，如 T('tree.' + k + '.t')）
  const isDyn = k => k.endsWith('.') || k.endsWith('<dynamic>');
  const used = new Set([...js.matchAll(/\bT\(\s*'([^']+)'/g)].map(x => x[1]));
  [...js.matchAll(/\bT\(\s*'([^']+)'\s*\+/g)].forEach(x => used.add(x[1] + '<dynamic>'));
  const unknown = [...used].filter(k => !isDyn(k) && kz.indexOf(k) < 0);
  if (unknown.length) fail('代码引用了字典里没有的键：' + unknown.join(', '));
  else console.log('  ✓ 代码引用的 ' + (used.size - [...used].filter(isDyn).length) + ' 个键都有定义');

  // 漏翻检查：两边的值都不能是空串，也不能一模一样（分隔符类短串除外）
  for (const lang of ['zh', 'en']) {
    Object.keys(dicts[lang].L).forEach(k => {
      if (dicts[lang].L[k] === '') fail(lang + ' 的 ' + k + ' 是空串');
    });
  }
  // en 侧不允许出现中日韩字符与全角标点 —— 它们会在英文页面上留下中文痕迹
  const cjk = /[\u3400-\u9fff\u3000-\u303f\uff00-\uffef]/;
  let cjkHit = 0;
  for (const lang of ['en']) {
    for (const k of Object.keys(dicts[lang].L)) if (cjk.test(dicts[lang].L[k])) { cjkHit++; fail('en 的 ' + k + ' 含中文/全角字符'); }
    for (const k of Object.keys(dicts[lang].V)) if (cjk.test(dicts[lang].V[k])) { cjkHit++; fail('en 的 V["' + k + '"] 含中文/全角字符'); }
  }
  if (!cjkHit) console.log('  ✓ en 侧字典与枚举映射零中文、零全角字符（V 共 ' + Object.keys(dicts.en.V).length + ' 条）');

  console.log(n === 0 ? '\n全部通过' : '\n失败 ' + n + ' 项');
  process.exit(n === 0 ? 0 : 1);
}

const file = process.argv[2];
if (!file) { console.error('用法: node btm-selftest.js <btm_items.html>　或　node btm-selftest.js --i18n btm-view.tpl.html'); process.exit(2); }
const html = fs.readFileSync(file, 'utf8');

const dblock = html.match(/<script id="btm-data" type="application\/json">\n([\s\S]*?)\n<\/script>/);
const jsblock = html.match(/<script>\n([\s\S]*?)\n<\/script>/);
if (!dblock || !jsblock) { console.error('✗ 脚本块提取失败，HTML 结构可能被破坏'); process.exit(1); }
const data = dblock[1];
try { JSON.parse(data); } catch (e) { console.error('✗ 内嵌数据不是合法 JSON：' + e.message); process.exit(1); }

const cache = {};
function el(id) {
  return {
    id, textContent: '', innerHTML: '', value: '', rows: [], dataset: {},
    classList: {
      _s: new Set(),
      add(c) { this._s.add(c); }, remove(c) { this._s.delete(c); },
      toggle(c, f) { if (f === undefined) { this._s.has(c) ? this._s.delete(c) : this._s.add(c); } else { f ? this._s.add(c) : this._s.delete(c); } },
      contains(c) { return this._s.has(c); }
    },
    appendChild() {}, addEventListener() {}, querySelectorAll() { return []; },
    querySelector() { return null; }, getAttribute() { return null; }, setAttribute() {},
    onclick: null, onchange: null, checked: false
  };
}
const store = {};
const sandbox = {
  console, setTimeout, clearTimeout, Date, JSON, Math, Object, Array, String, Number,
  parseInt, parseFloat, isNaN, RegExp, Error, Boolean,
  navigator: { language: 'zh-CN', languages: ['zh-CN', 'zh'] },   // 桩的默认语言 = zh
  document: {
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    title: '',
    getElementById(id) {
      if (id === 'btm-data') return { textContent: data };
      if (!cache[id]) cache[id] = el(id);
      return cache[id];
    },
    querySelectorAll() { return []; }, querySelector() { return null; },
    addEventListener() {}, createElement() { return el('x'); },
    body: { appendChild() {}, removeChild() {} }
  },
  localStorage: {
    getItem(k) { return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null; },
    setItem(k, v) { store[k] = v; },
    removeItem(k) { delete store[k]; }
  },
  Blob: function () {}, URL: { createObjectURL() { return ''; } }
};
sandbox.window = sandbox;
vm.createContext(sandbox);
try { vm.runInContext(jsblock[1], sandbox, { filename: 'btm-view.js' }); }
catch (e) { console.error('✗ 页面脚本执行失败：' + e.message); process.exit(1); }

const S = sandbox.S, ITEMS = sandbox.ITEMS, SECTIONS = sandbox.SECTIONS;
/* 直接借用页面自己的字典与取值映射来推导「当前语言的期望文案」，
 * 这样同一份断言对 zh（中英对照）与 en（纯英文）两种渲染都成立。 */
const T = sandbox.T, show = sandbox.show, uidGroupLabel = sandbox.uidGroupLabel;
const rxEsc = s => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/* 字典模板里占位符之前的字面前缀，用来断言「这句话出现过」而不写死整句 */
const literalHead = k => { const s = sandbox.L[k]; const i = s.indexOf('{'); return i < 0 ? s : s.slice(0, i); };
let fail = 0;
const count = (s, re) => (s.match(re) || []).length;
const pass = (m) => console.log('  ✓ ' + m);
const bad = (m, e) => { fail++; console.log('  ✗ ' + m + (e ? ' -> ' + e : '')); };

console.log('条目 ' + ITEMS.length + '　全字段列 ' + sandbox.ALLCOLS.length);
pass('初始加载与表格渲染');

try { S.sortCol = 'identifier'; S.sortAsc = true; sandbox.renderTable(); pass('按列排序后重建'); }
catch (e) { bad('排序', e.message); }
// 筛选用数据里真实存在的片段，避免把断言绑死在某台机器的软件名上
const qProbe = String(ITEMS[0].identifier_base || ITEMS[0].name || 'a').slice(0, 5);
try { S.q = qProbe; sandbox.renderTable(); pass('关键字筛选'); }
catch (e) { bad('关键字筛选', e.message); }
try { S.q = ''; S.status = 'disallowed'; sandbox.renderTable(); pass('状态筛选'); }
catch (e) { bad('状态筛选', e.message); }
try { S.status = ''; S.cols = ['name']; sandbox.renderTable(); pass('单列渲染'); }
catch (e) { bad('单列渲染', e.message); }
S.cols = sandbox.ALLCOLS.slice();
try { sandbox.renderColPanel(); pass('列选择面板'); }
catch (e) { bad('列面板', e.message); }

const stats = {};
['parent', 'embedded', 'bundle', 'scope', 'vendor', 'config', 'exec', 'generation'].forEach(function (m) {
  try {
    S.treeMode = m; S.open = {}; S.treeCollapse = false;
    sandbox.renderTree();
    const out = cache['treewrap'].innerHTML;
    if (!out) throw new Error('输出为空');
    const nodes = count(out, /class="trow"/g), groups = count(out, /gnode/g);
    stats[m] = { nodes, groups, html: out };
    const items = nodes - groups;
    if (items > ITEMS.length) throw new Error('条目节点 ' + items + ' 超过总数 ' + ITEMS.length + '（有重复挂载）');
    pass('树 ' + m.padEnd(10) + ' 条目 ' + String(items).padStart(2) + '（≤' + ITEMS.length + '），分组 '
      + String(groups).padStart(2) + '，嵌套层 ' + String(count(out, /class="tkids"/g)).padStart(2)
      + '，备注 ' + count(out, /class="gnote"/g));
  } catch (e) { bad('树 ' + m, e.message); }
});

/* ------------------------------------------------------------------
 * 回归测试：折叠后必须还能展开（历史 bug：折叠正常、展开失效）
 *
 * 根因是原实现用 `row.parentNode.querySelector('.tkids')` 判断节点有没有子节点，
 * 而折叠状态下 .tkids 根本不会被渲染，于是判断恒为假、再也展不开。
 * 修法：节点把「有子节点」写进 data-kids 属性。
 * 这里既校验标记契约，也真调一次 onclick 验证状态确实翻转。
 * ------------------------------------------------------------------ */

// 让 treewrap 的 querySelectorAll 能从刚渲染出的 HTML 里解析出行对象。
// 同一份 innerHTML 必须返回同一批对象 —— renderTree 把 onclick 挂在这批对象上，
// 若每次调用都新建对象，测试拿到的就是没挂 handler 的空壳。
let _rowsHtml = null, _rowsCache = null;
cache['treewrap'].querySelectorAll = function (sel) {
  if (sel !== '.trow') return [];
  if (this.innerHTML === _rowsHtml && _rowsCache) return _rowsCache;
  const rows = [];
  const tagRe = /<div class="trow"([^>]*)>/g;
  let m;
  while ((m = tagRe.exec(this.innerHTML))) {
    const attrs = {};
    const aRe = /([a-zA-Z-]+)="([^"]*)"/g;
    let a;
    while ((a = aRe.exec(m[1]))) attrs[a[1]] = a[2];
    rows.push({
      attrs,
      getAttribute(n) { return Object.prototype.hasOwnProperty.call(attrs, n) ? attrs[n] : null; },
      parentNode: { querySelector() { return null; } },
      onclick: null
    });
  }
  _rowsHtml = this.innerHTML; _rowsCache = rows;
  return rows;
};

// 非叶子节点的 caret 是 class="caret">，叶子是 class="caret leaf">（两者都含 "caret」，故必须带结尾的 > 或空格区分）
const caretNonLeafRe = /class="caret">/g, caretLeafRe = /class="caret leaf">/g;

try {
  S.treeCollapse = true; S.open = {}; S.treeMode = 'parent'; sandbox.renderTree();
  const out = cache['treewrap'].innerHTML;
  const rows = count(out, /class="trow"/g);
  const kidsBlocks = count(out, /class="tkids"/g);
  const marked = count(out, /data-kids="1"/g);
  const nonLeaf = count(out, caretNonLeafRe);

  if (kidsBlocks !== 0) throw new Error('默认折叠状态下不该渲染 .tkids，实际有 ' + kidsBlocks + ' 个');
  if (marked === 0) throw new Error('折叠状态下没有任何节点带 data-kids —— 将无法展开（正是原 bug）');
  if (marked !== nonLeaf) throw new Error('带 data-kids 的节点 ' + marked + ' 个，不等于有子节点的行 ' + nonLeaf + ' 个（标记不完整）');

  // 真调一次 onclick，验证折叠态下点击能展开
  const target = cache['treewrap'].querySelectorAll('.trow').filter(r => r.getAttribute('data-kids') === '1' && !r.getAttribute('data-id'))[0];
  if (!target) throw new Error('找不到可点击的父级节点');
  const key = target.getAttribute('data-k');
  target.onclick();
  if (S.open[key] !== true) throw new Error('点击折叠态节点后 S.open 未变为 true（展开失败）');
  let after = cache['treewrap'].innerHTML;
  if (count(after, /class="tkids"/g) === 0) throw new Error('点击后仍无 .tkids，界面没有真的展开');

  // 再点一次，验证能折回去（双向）
  const again = cache['treewrap'].querySelectorAll('.trow').filter(r => r.getAttribute('data-k') === key)[0];
  if (!again) throw new Error('重新渲染后找不到同一节点');
  again.onclick();
  if (S.open[key] !== false) throw new Error('再次点击后 S.open 未变为 false（折叠失败）');

  pass('折叠/展开双向切换：' + rows + ' 行中 ' + marked + ' 行可展开，点击后状态与界面均正确翻转');
} catch (e) { bad('折叠-展开回归测试', e.message); }

try {
  S.treeCollapse = false; S.open = {}; S.treeMode = 'parent'; sandbox.renderTree();
  const out = cache['treewrap'].innerHTML;
  const marked = count(out, /data-kids="1"/g);
  const nonLeaf = count(out, caretNonLeafRe), leaves = count(out, caretLeafRe);
  if (marked !== nonLeaf) throw new Error('展开态标记不一致：data-kids ' + marked + ' vs 有子节点的行 ' + nonLeaf);
  if (nonLeaf + leaves !== count(out, /class="trow"/g)) throw new Error('caret 分类不完备：' + nonLeaf + '+' + leaves);
  pass('展开态标记一致：' + nonLeaf + ' 个可折叠节点 / ' + leaves + ' 个叶子');
} catch (e) { bad('展开态标记', e.message); }

S.treeCollapse = false;
try { for (let i = 0; i < ITEMS.length; i++) sandbox.openDetail(ITEMS[i]); pass('详情面板渲染全部 ' + ITEMS.length + ' 条'); }
catch (e) { bad('详情面板', e.message); }

/* 详情面板必须把该条记录**所有**分组的非空字段都列出来。
 * 这是一条回归测试：历史实现写成 `if (gi > 0 && GROUPS.indexOf(g) >= 0) return;`，
 * 它会跳过 GROUPS 里除第一个以外的全部组 —— 面板只剩「记录组」一组、
 * 其余 40 多个字段静默消失，而且界面看起来完全正常，没人会发现。
 * 断言按「分组数」而非「字段数」比对，所以加列、改分组都不会误报。 */
try {
  let checked = 0, worstG = Infinity;
  ITEMS.forEach(it => {
    const want = new Set();
    sandbox.ALLCOLS.forEach(c => { if (!sandbox.isNullish(it[c]) && it[c] !== false) want.add(sandbox.colGrp(c)); });
    sandbox.openDetail(it);
    const html = cache['detail'].innerHTML;
    const href = [...html.matchAll(/class="gtitle">[^<]*</g)].length;
    const rows = (html.match(/<tr>/g) || []).length;
    checked++;
    if (want.size < worstG) worstG = want.size;
    if (href !== want.size) bad('详情「' + (it.identifier || it.name) + '」只列了 ' + href + ' 组，实际有值的组有 ' + want.size + ' 个');
    else if (rows < want.size) bad('详情「' + (it.identifier || it.name) + '」字段行 ' + rows + ' 少于分组数 ' + want.size);
  });
  pass('详情面板逐条覆盖全部有值分组（' + checked + ' 条，单条最少 ' + worstG + ' 组）');
} catch (e) { bad('详情面板分组完整性', e.message); }
try { sandbox.renderHelp(); pass('字段说明页'); }
catch (e) { bad('字段说明页', e.message); }
try { ['table', 'tree', 'help'].forEach(v => sandbox.setView(v)); pass('视图切换'); }
catch (e) { bad('视图切换', e.message); }

// 内容抽查：断言全部从当前数据推导，不绑定任何一台机器的软件清单
if (stats['parent']) {
  const p = stats['parent'].html;
  const dev = ITEMS.filter(it => String(it.type_mechanism) === 'developer')[0];
  const grpLabel = SECTIONS.length ? uidGroupLabel(SECTIONS[0].uid) : '';
  if (!grpLabel || p.indexOf(grpLabel) < 0) bad('归属树缺记录组层级（期望「' + grpLabel + '」）');
  else if (dev && p.indexOf(String(dev.identifier)) < 0) bad('归属树缺开发者父节点');
  else pass('归属树：含记录组层级与开发者父节点');
}
if (stats['embedded']) {
  const byId = {};
  ITEMS.forEach(it => { if (it.identifier && !byId[it.identifier]) byId[it.identifier] = it; });
  let hasMismatch = false;
  ITEMS.forEach(it => {
    let l = it.embedded_item_identifiers || [];
    if (Object.prototype.toString.call(l) !== '[object Array]') {
      l = String(l).split('|').map(x => x.trim()).filter(Boolean);
    }
    l.forEach(e => {
      const c = byId[e];
      if (c && c.parent_identifier && c.parent_identifier !== it.identifier) hasMismatch = true;
    });
  });
  const h = stats['embedded'].html;
  if (!hasMismatch) pass('嵌入树：本次数据两向自洽，无需标注不一致');
  else if (h.indexOf(literalHead('tree.embed.mismatch')) < 0) bad('嵌入树没标出「自述父级不一致」');
  else pass('嵌入树：标出了「自述父级与嵌入声明不一致」的条目');
}

/* ⑥⑦ 两棵位置树：必须真的按「配置 / 可执行」分开，并覆盖各自的类别。
 * 抽成函数是因为这条检查对英文标签格外敏感 —— 英文类别名 "Application Support"
 * 会撞上目录路径 /Library/Application Support/…，所以两种语言都要各验一遍。 */
function checkLocTrees(cfg, exe, tag){
  if (!cfg || !exe) { bad(tag + '位置树缺失'); return; }

  // ① 两棵树的数据源必须不同：配置树的类别取自 config_kind 列、可执行树取自 exec_scope 列。
  //    「该出现哪些类别」由当前数据推导，因此换一台机器、换一份快照同样成立。
  const kindSet = (col) => {
    const s = new Set();
    ITEMS.forEach(it => { const v = it[col]; if (v && v !== '(null)') s.add(String(v)); });
    return Array.from(s);
  };
  const cfgKinds = kindSet('config_kind');
  const exeKinds = kindSet('exec_scope');
  /* 判定「某类别出现在这棵树里」必须匹配**分组标签元素**，不能用裸子串：
   * 英文标签 "Application Support" 会正好撞上目录路径 /Library/Application Support/…，
   * 裸子串判定会把配置树里的一条普通路径误报成「串台」。 */
  const hasKind = (html, raw) =>
    new RegExp('<span class="tlabel gnode">' + rxEsc(show(raw)) + '</span>').test(html);
  const missCfg = cfgKinds.filter(k => !hasKind(cfg, k));
  const missExe = exeKinds.filter(k => !hasKind(exe, k));
  if (missCfg.length) bad(tag + '配置树缺类别：' + missCfg.join('、'));
  else if (missExe.length) bad(tag + '可执行树缺类别：' + missExe.join('、'));
  else pass(tag + '两棵位置树类别齐备（配置 ' + cfgKinds.length + ' 类 / 可执行 ' + exeKinds.length + ' 类，取自数据列）');

  // ② 类别不得串台：配置树里不该出现只属于可执行的类别，反之亦然。
  //    这是"两棵树确实建立在两个不同字段上"的硬证据。
  const cfgOnly = ['系统守护进程配置', '全局代理配置', '用户代理配置', '应用包内嵌组件'];
  const exeOnly = ['系统特权 Helper', '系统应用支持目录', '本地安装目录（/usr/local）', '应用包内（Contents/MacOS）'];
  const leakInExe = cfgOnly.filter(k => hasKind(exe, k));
  const leakInCfg = exeOnly.filter(k => hasKind(cfg, k));
  if (leakInExe.length || leakInCfg.length) {
    bad(tag + '两棵树类别串台：可执行树混入 ' + (leakInExe.join('、') || '无') + '；配置树混入 ' + (leakInCfg.join('、') || '无'));
  } else {
    pass(tag + '两棵树互不串台：配置类别只出现在⑥，可执行类别只出现在⑦');
  }

  // ③ 桶的归属必须与数据吻合：无配置路径 = URL 为 (null) 的条数，无独立可执行文件 = 没有 Executable Path 的条数
  const nul = sandbox.isNullish;
  const noUrl = ITEMS.filter(it => nul(it.url_path) || it.url_path === '(null)').length;
  const noExec = ITEMS.filter(it => nul(it.executable_path) || it.executable_path === '(null)').length;
  // 「N 项」的计数后缀也取自字典（中文「 项」/ 英文「 items」），否则换语言就对不上
  const bucket = (html, rawLabel) => {
    const label = show(rawLabel);
    const m = html.match(new RegExp('<span class="tlabel gnode">' + rxEsc(label)
      + '</span><span class="gcount">' + T('items', '(\\d+)')));
    return m ? parseInt(m[1], 10) : -1;
  };
  const bCfg = bucket(cfg, '无配置路径'), bExe = bucket(exe, '无独立可执行文件');
  if (bCfg !== noUrl) bad(tag + '⑥「无配置路径」桶 ' + bCfg + ' ≠ URL 为 (null) 的 ' + noUrl + ' 条');
  else if (bExe !== noExec) bad(tag + '⑦「无独立可执行文件」桶 ' + bExe + ' ≠ 无 Executable Path 的 ' + noExec + ' 条');
  else pass(tag + '桶归属吻合：⑥无配置路径 ' + bCfg + ' 条 / ⑦无独立可执行文件 ' + bExe + ' 条（各自有落点的 '
    + (ITEMS.length - bCfg) + ' 与 ' + (ITEMS.length - bExe) + ' 条）');
}

checkLocTrees(stats['config'] && stats['config'].html, stats['exec'] && stats['exec'].html, '');

/* ==================================================================
 * 语言切换：一个 HTML 要同时装得下两种形态
 *
 * 主体断言跑的是页面默认语言（桩的 navigator = zh-CN）。
 * 这里在同一个已加载的页面里切到 en 再验一遍。重点不是重跑全部逻辑
 * —— 树的构建、桶归属、类别齐备都与语言无关，跑一遍就够 ——
 * 而是三件「只有切换才暴露」的事：
 *   1. 视图状态不被切换重置（筛选/排序/列选择/树展开），且选择被记住
 *   2. en 形态下所有视图的**可见文案零中文**（语言切换器按钮除外，那是语言自称）
 *   3. 位置树的类别标签在英文下仍对得上（历史上英文标签撞过目录路径）
 * ================================================================== */
console.log('');
console.log('—— 语言切换 ——');

const CJK = /[\u3400-\u9fff\u3000-\u303f\uff00-\uffef]/;
const cjkSample = (s) => {
  const i = s.search(CJK);
  return i < 0 ? null : JSON.stringify(s.slice(Math.max(0, i - 30), i + 30));
};

/* 英文形态扫描前，先把**数据原值**剥掉 —— 软件名、路径、开发者名这些本来就不该被翻译，
 * 一台机器上装个中文名的应用（「坚果云」「UU远程」…）并不代表页面漏翻。
 * 但 V 映射表里列出的那些枚举值必须留在扫描范围内：它们**应该**被换成英文，
 * 漏翻就是要报错的（详情面板忘记调 show() 的历史 bug 正是靠这条抓出来的）。
 * 也就是说「哪些中文算数据、哪些算界面」不是写死的，而是从页面自己的映射表推出来的。 */
const TRANSLATED = new Set(Object.keys(sandbox.I18N.en.v));
const DATA_VALUES = (() => {
  const set = new Set();
  const add = (v) => { if (typeof v === 'string' && v.length >= 2 && !TRANSLATED.has(v)) set.add(v); };
  ITEMS.forEach(it => sandbox.ALLCOLS.forEach(c => {
    const v = it[c];
    if (Object.prototype.toString.call(v) === '[object Array]') v.forEach(add); else add(v);
  }));
  [sandbox.DATA.source_file, sandbox.DATA.captured_at, sandbox.DATA.host, sandbox.DATA.sort_preset].forEach(add);
  return Array.from(set).sort((a, b) => b.length - a.length);   // 长值先替，避免短值先把长值切碎
})();
const stripData = (html) => {
  let s = html;
  for (const v of DATA_VALUES) s = s.split(sandbox.esc(v)).join('\u00a7');
  return s;
};

try {
  if (sandbox.BTM_LANG !== 'zh') throw new Error('桩的默认语言应为 zh，实际为 ' + sandbox.BTM_LANG);

  // 先摆一个「非默认」状态，切语言后必须原样保留
  S.view = 'tree'; S.q = qProbe; S.status = 'enabled'; S.treeMode = 'config';
  S.cols = ['uid', 'name', 'identifier_base']; S.treeCollapse = false; S.open = {};
  sandbox.renderTree();
  const toOpen = cache['treewrap'].querySelectorAll('.trow')
    .filter(r => r.getAttribute('data-kids') === '1')[0];
  if (!toOpen) throw new Error('找不到可展开的节点，无法验证展开状态是否保留');
  toOpen.onclick();
  const openBefore = JSON.stringify(S.open);
  const statusBefore = S.status, colsBefore = S.cols.join(','), qBefore = S.q;

  sandbox.setLang('en');
  if (sandbox.BTM_LANG !== 'en') throw new Error('BTM_LANG 没切成 en');
  if (sandbox.L !== sandbox.I18N.en.l) throw new Error('L 没有指向 en 字典');
  if (sandbox.V !== sandbox.I18N.en.v) throw new Error('V 没有指向 en 映射表');
  if (sandbox.document.title !== sandbox.I18N.en.l['doc.title']) throw new Error('document.title 没跟着换');

  if (S.view !== 'tree') throw new Error('视图被切换重置');
  if (S.q !== qBefore || S.status !== statusBefore) throw new Error('筛选条件被切换重置');
  if (S.cols.join(',') !== colsBefore) throw new Error('列选择被切换重置');
  if (JSON.stringify(S.open) !== openBefore) throw new Error('树的展开状态被切换重置');
  if (store['btm.lang'] !== 'en') throw new Error('语言选择没写进 localStorage');
  pass('切到 en：视图/筛选/列选择/树展开全部保留，选择已记入 localStorage');

  // en 形态逐视图扫描可见文案
  S.treeCollapse = false;
  const views = {};
  ['parent', 'embedded', 'bundle', 'scope', 'vendor', 'config', 'exec', 'generation'].forEach(m => {
    S.treeMode = m; S.open = {}; sandbox.renderTree(); views['树 ' + m] = cache['treewrap'].innerHTML;
  });
  sandbox.renderTable(); views['表格'] = cache['tablewrap'].innerHTML;
  sandbox.renderColPanel(); views['列面板'] = cache['colpanel'].innerHTML;
  sandbox.renderHelp(); views['字段说明'] = cache['help'].innerHTML;
  views['页头'] = cache['stat'].innerHTML + cache['sub'].textContent + cache['orderHint'].innerHTML;

  let leak = 0, details = 0;
  Object.keys(views).forEach(k => {
    const b = cjkSample(stripData(views[k]));
    if (b) { leak++; bad('en 形态「' + k + '」含中文/全角：' + b); }
  });
  S.sel = null;
  ITEMS.forEach(it => {
    sandbox.openDetail(it); details++;
    const b = cjkSample(stripData(cache['detail'].innerHTML));
    if (b) { leak++; if (leak <= 5) bad('en 形态 详情「' + (it.name || it.identifier_base) + '」含中文：' + b); }
  });
  if (!leak) pass('en 形态：' + Object.keys(views).length + ' 个视图 + ' + details + ' 条详情，界面文案零中文/零全角'
    + '（已剥除 ' + DATA_VALUES.length + ' 个数据原值）');

  // 位置树的类别归属在英文下同样成立
  checkLocTrees(views['树 config'], views['树 exec'], 'en 形态 ');

  // 切回中文
  sandbox.setLang('zh');
  if (sandbox.BTM_LANG !== 'zh') throw new Error('切不回 zh');
  sandbox.renderHelp();
  if (!CJK.test(cache['help'].innerHTML)) throw new Error('zh 形态的字段说明里没有中文，字典可能没换回来');
  if (store['btm.lang'] !== 'zh') throw new Error('切回 zh 后 localStorage 没更新');
  pass('切回 zh：文案恢复中文，往返切换可用');
} catch (e) { bad('语言切换', e.message); }

console.log(fail === 0 ? '\n全部通过' : '\n失败 ' + fail + ' 项');
process.exit(fail === 0 ? 0 : 1);
