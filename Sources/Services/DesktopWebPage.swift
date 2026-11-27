//
//  DesktopWebPage.swift
//  AlienMAC
//
//  桌面端控制页面（浏览器打开，和手机版共用同一套 HTTP / SSE 接口）
//  面板顺序、措辞、开关与滑块都对齐 app 主界面的「灯效编辑」一栏
//

import Foundation

enum DesktopWebPage {

    static let html = #"""
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AlienMAC · 桌面控制台</title>
<link rel="icon" href="/api/logo.png">
<style>
*{box-sizing:border-box}
html,body{margin:0;padding:0;background:#04070c;color:#e6ecf5;
  font:14px/1.5 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif}
body{min-height:100vh;
  background:
    radial-gradient(120% 90% at 22% 18%, #0a1c30 0%, #05080f 55%, #000 100%),
    radial-gradient(70% 60% at 92% 8%, rgba(140,50,230,.16), transparent 60%);}
a{color:inherit;text-decoration:none}
.shell{max-width:1280px;margin:0 auto;padding:22px 24px 28px}

/* 顶栏 */
.top{display:flex;align-items:center;gap:14px;margin-bottom:16px}
.mark{height:52px;width:auto;flex:none;display:block;
  filter:saturate(1.06) drop-shadow(0 0 16px rgba(56,208,255,.55))}
.top h1{margin:0;font-size:20px;font-weight:650;letter-spacing:.2px}
.top p{margin:2px 0 0;font-size:12px;color:#8ba0bb}
.top .push{margin-left:auto;display:flex;align-items:center;gap:10px}
.pill{display:flex;align-items:center;gap:7px;padding:7px 13px;border-radius:999px;font-size:12px;
  background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);color:#c2cfdf;white-space:nowrap}
.pill i{width:7px;height:7px;border-radius:50%;background:#31e58a;box-shadow:0 0 9px #31e58a}
.pill.off i{background:#ff5a5a;box-shadow:0 0 9px #ff5a5a}
.link{padding:7px 13px;border-radius:999px;font-size:12px;color:#9fb4cc;
  border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.04);transition:.15s}
.link:hover{color:#fff;border-color:rgba(0,200,255,.6);background:rgba(0,170,255,.12)}

/* 布局 */
.main{display:grid;grid-template-columns:minmax(0,1fr) 396px;gap:16px;align-items:start}
.card{background:rgba(255,255,255,.052);border:1px solid rgba(255,255,255,.1);
  border-radius:18px;padding:15px;backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px)}
.card h2{margin:0 0 11px;font-size:13px;font-weight:600;letter-spacing:.3px;
  color:#c3d0e0;display:flex;align-items:center;justify-content:space-between;gap:10px}
.card h2 span{font:11.5px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:#7ad9ff;letter-spacing:0}
.card h2 .muted{color:#7e8fa6}

/* 机身预览 */
.stage{padding:16px 16px 12px;display:flex;flex-direction:column;gap:10px;position:sticky;top:16px}
.stage img{display:block;width:100%;border-radius:14px;background:#04070c;
  border:1px solid rgba(255,255,255,.07)}
.stage .foot{display:flex;align-items:center;gap:10px;font-size:11.5px;color:#7e8fa6;line-height:1.6}
.stage .foot b{color:#a9bdd4;font-weight:500}

/* 控制器 */
.side{display:flex;flex-direction:column;gap:13px}
.row{display:flex;align-items:center;gap:8px}
.grid3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
.btn{border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.055);color:#dfe8f5;
  border-radius:11px;padding:9px 11px;font-size:12.5px;font-weight:520;text-align:center;
  transition:.15s;cursor:pointer;user-select:none;min-width:0;white-space:nowrap;
  overflow:hidden;text-overflow:ellipsis}
.btn:hover{background:rgba(255,255,255,.1)}
.btn:active{transform:scale(.985)}
.btn.on{border-color:rgba(0,190,255,.75);background:rgba(0,170,255,.17);color:#fff;
  box-shadow:inset 0 0 18px rgba(0,170,255,.22)}
.btn.small{padding:6px 10px;font-size:11.5px}
.btn.ghost{background:transparent}
.btn.dim{opacity:.45;pointer-events:none}
.btn.primary{flex:1;border-color:rgba(0,200,255,.8);color:#fff;
  background:linear-gradient(135deg,rgba(0,178,255,.55),rgba(120,80,255,.5));
  box-shadow:0 6px 18px rgba(0,140,255,.3)}
.btn.primary:hover{filter:brightness(1.08)}

/* 滑块 */
.slider{display:flex;align-items:center;gap:12px}
input[type=range]{-webkit-appearance:none;appearance:none;flex:1;height:26px;background:transparent;margin:0}
input[type=range]::-webkit-slider-runnable-track{height:8px;border-radius:6px;
  background:linear-gradient(90deg,#00c2ff,#7a5cff)}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:20px;height:20px;border-radius:50%;
  margin-top:-6px;background:#fff;box-shadow:0 0 12px rgba(0,190,255,.85);border:0;cursor:pointer}
input[type=range]::-moz-range-track{height:8px;border-radius:6px;background:linear-gradient(90deg,#00c2ff,#7a5cff)}
input[type=range]::-moz-range-thumb{width:20px;height:20px;border:0;border-radius:50%;background:#fff}

/* 开关 */
.sw-line{display:flex;align-items:center;gap:9px;padding:7px 0}
.sw-line .switch{width:38px;height:22px;border-radius:999px;flex:none;position:relative;cursor:pointer;
  background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.14);transition:.18s}
.sw-line .switch b{position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;
  background:#cfd9e6;transition:.18s}
.sw-line .switch.on{background:rgba(0,190,255,.55);border-color:rgba(0,190,255,.7);
  box-shadow:0 0 12px rgba(0,180,255,.35)}
.sw-line .switch.on b{left:18px;background:#fff}
.sw-line .label{font-size:12.5px;color:#cfdbeb}
.sub{font-size:11.5px;color:#7e8fa6;margin:2px 0 0}

/* 灯区 */
.zones{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
.zone{position:relative;border:1px solid rgba(255,255,255,.1);background:rgba(255,255,255,.04);
  border-radius:11px;padding:11px 6px 8px;font-size:12px;color:#a9b7cc;text-align:center;
  overflow:hidden;transition:.15s;cursor:pointer}
.zone span{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.zone .stripe{position:absolute;left:0;right:0;top:0;height:3px;filter:saturate(1.3)}
.zone:hover{background:rgba(255,255,255,.09)}
.zone.sel{color:#fff;border-color:rgba(0,195,255,.8);background:rgba(0,170,255,.16);
  box-shadow:0 0 16px rgba(0,170,255,.22)}

/* 颜色 */
.mainColor{display:flex;align-items:center;gap:10px}
.dot{width:34px;height:34px;border-radius:50%;flex:none;border:1px solid rgba(255,255,255,.4);
  box-shadow:0 0 18px currentColor}
.hex{font:13px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:#9fb2ca}
.pickerRow{display:flex;align-items:center;gap:10px;margin-top:11px}
.pickerRow input[type=color]{width:44px;height:34px;border:1px solid rgba(255,255,255,.18);
  border-radius:11px;background:transparent;padding:2px;cursor:pointer}
.swatches{display:grid;grid-template-columns:repeat(8,1fr);gap:7px;margin-top:12px}
.sw{height:30px;border-radius:9px;border:1px solid rgba(255,255,255,.16);cursor:pointer;transition:.15s}
.sw:hover{transform:translateY(-1px)}
.sw.sel{outline:2px solid #fff;outline-offset:2px}

/* 效果 / 预设 / 每区动作 */
.effects{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:7px}
.presets{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
.pre{display:flex;align-items:center;gap:9px;border:1px solid rgba(255,255,255,.1);
  background:rgba(255,255,255,.04);border-radius:11px;padding:9px 10px;font-size:12.5px;
  color:#ccd8e8;cursor:pointer;transition:.15s;min-width:0}
.pre span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.pre:hover{background:rgba(255,255,255,.09)}
.pre .c{width:10px;height:10px;border-radius:50%;flex:none;box-shadow:0 0 10px currentColor}

.actions{display:flex;flex-direction:column;gap:6px;margin-top:2px}
.actRow{display:flex;align-items:center;gap:8px;padding:6px 8px;border-radius:10px;
  background:rgba(255,255,255,.035);border:1px solid rgba(255,255,255,.07)}
.actRow .c{width:8px;height:8px;border-radius:50%;flex:none;box-shadow:0 0 8px currentColor}
.actRow .name{font-size:12px;color:#d5e1ef;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:86px}
.actRow .sum{font-size:11px;color:#8295ad;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1}
.actRow .loop{font-size:11.5px;color:#7ad9ff;cursor:pointer;padding:2px 6px;border-radius:7px;
  border:1px solid rgba(0,190,255,.3);background:rgba(0,190,255,.08)}
.actRow .loop.off{color:#8ba0bb;border-color:rgba(255,255,255,.14);background:transparent}

.saveRow{display:flex;gap:8px;margin-top:9px}
.saveRow input{flex:1;min-width:0;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.14);
  border-radius:10px;color:#e6ecf5;font-size:12.5px;padding:8px 10px;outline:none}
.saveRow input:focus{border-color:rgba(0,190,255,.6)}

.foot{display:flex;justify-content:space-between;gap:14px;margin-top:16px;
  font-size:11.5px;color:#6f8098;line-height:1.6}
.toast{position:fixed;left:50%;bottom:26px;transform:translate(-50%,16px);
  background:rgba(10,18,30,.95);border:1px solid rgba(0,190,255,.5);color:#dff3ff;
  padding:9px 16px;border-radius:999px;font-size:13px;opacity:0;pointer-events:none;
  transition:.25s;box-shadow:0 10px 28px rgba(0,0,0,.5);z-index:9;white-space:nowrap}
.toast.show{opacity:1;transform:translate(-50%,0)}

@media (max-width:1060px){
  .main{grid-template-columns:minmax(0,1fr)}
  .stage{position:static}
  .shell{padding:16px}
}
</style>
</head>
<body>
<div class="shell">

  <div class="top">
    <img class="mark" src="/api/logo.png" alt="AlienMAC">
    <div>
      <h1>AlienMAC</h1>
      <p id="subtitle">正在连接…</p>
    </div>
    <div class="push">
      <div class="pill" id="status"><i></i><b id="statusText">连接中</b></div>
      <a class="link" href="/mobile">手机版</a>
    </div>
  </div>

  <div class="main">
    <section class="card stage">
      <h2>机身预览 <span id="modelHint">与 app 同步</span></h2>
      <img id="model" alt="AlienMAC">
      <div class="foot">
        <span><b>这是 app 同一块 3D 视图</b>，角度、配色、屏幕壁纸都跟主界面一致，改灯效会立刻反映过来。</span>
      </div>
    </section>

    <aside class="side">

      <!-- 灯效编辑 -->
      <section class="card">
        <h2>灯效编辑 <span id="zoneCount">13 个灯区</span></h2>
        <div class="mainColor">
          <div class="dot" id="mainDot"></div>
          <div>
            <div class="sub">主颜色</div>
            <div class="hex" id="mainHex">#FF33CC</div>
          </div>
          <div class="btn small ghost" id="btnPick" style="margin-left:auto">取色器</div>
        </div>
        <div class="pickerRow" id="pickerRow" style="display:none">
          <input id="picker" type="color" value="#ff33cc">
          <div class="hex" id="pickerHex">#FF33CC</div>
          <div class="btn small" id="btnApplyColor" style="padding:7px 14px">用这个颜色</div>
        </div>
        <div class="swatches" id="swatches"></div>
        <div style="margin-top:14px">
          <div class="sw-line" style="padding:0 0 6px">
            <div class="label">亮度</div>
            <div style="margin-left:auto" class="hex" id="briText">100%</div>
          </div>
          <div class="slider"><input id="bri" type="range" min="0" max="100" step="1" value="100"></div>
        </div>
        <div class="grid3" style="margin-top:10px">
          <div class="btn" data-eff="color">常亮</div>
          <div class="btn" data-eff="pulse">脉冲</div>
          <div class="btn" data-eff="morph">渐变</div>
          <div class="btn" data-eff="breathing">呼吸</div>
          <div class="btn" data-eff="spectrum">光谱</div>
          <div class="btn" data-eff="wave">光波</div>
          <div class="btn" data-eff="scanner">扫描</div>
        </div>
        <div id="tempoWrap" style="margin-top:11px;display:none">
          <div class="sw-line" style="padding:0 0 6px">
            <div class="label" id="tempoLabel">速度</div>
            <div style="margin-left:auto" class="hex" id="tempoText">2000 ms</div>
          </div>
          <div class="slider"><input id="tempo" type="range" min="500" max="8000" step="250" value="2000"></div>
        </div>
      </section>

      <!-- 触摸板细调 -->
      <section class="card">
        <h2>触摸板细调 <span class="muted" id="btnPadReset" style="cursor:pointer">恢复默认</span></h2>
        <div class="sw-line">
          <div class="switch" id="swPadFollow"><b></b></div>
          <div class="label">整面背光跟随灯区色</div>
        </div>
        <div class="slider">
          <input id="padBri" type="range" min="0" max="100" step="1" value="100">
          <div class="hex" id="padBriText">100%</div>
        </div>
        <div class="sub" style="margin-top:2px">整面亮度</div>
        <div class="sw-line" style="margin-top:8px">
          <div class="switch" id="swEdgeFollow"><b></b></div>
          <div class="label">边光跟随灯区色</div>
        </div>
        <div class="sw-line">
          <div class="switch" id="swEdgeShow"><b></b></div>
          <div class="label">显示边光</div>
        </div>
        <div class="slider">
          <input id="edgeBri" type="range" min="0" max="100" step="1" value="100">
          <div class="hex" id="edgeBriText">100%</div>
        </div>
        <div class="sub" style="margin-top:2px">边光强度</div>
      </section>

      <!-- 应用 / 撤销 -->
      <section class="card">
        <div class="row">
          <div class="btn primary" id="btnApply">应用</div>
          <div class="btn" id="btnCancel" style="flex:none;padding:9px 16px">取消</div>
        </div>
        <div class="grid3" style="margin-top:10px">
          <div class="btn" id="btnUndo">撤销</div>
          <div class="btn" id="btnRedo">重做</div>
          <div class="btn" id="btnToggle">关灯</div>
        </div>
        <div class="sub" style="margin-top:8px">调色即时生效，无需再点应用</div>
      </section>

      <!-- 每区动作 -->
      <section class="card">
        <h2>每区动作
          <span style="display:flex;gap:10px;align-items:center">
            <a id="btnClearActions" style="cursor:pointer;color:#8295ad">清空</a>
            <a id="btnAssign" style="cursor:pointer;color:#7ad9ff">＋ 指派</a>
          </span>
        </h2>
        <div id="actionHint" class="sub">选中灯区后可单独指派效果，让它不再跟随全局</div>
        <div class="actions" id="actions"></div>
        <div class="row" style="margin-top:11px">
          <div class="btn" id="btnSavePreset">存为预设</div>
        </div>
        <div class="saveRow" id="saveRow" style="display:none">
          <input id="presetName" placeholder="预设名称">
          <div class="btn small" id="btnSaveOk" style="flex:none;padding:8px 14px">保存</div>
        </div>
      </section>

      <!-- 快捷主题 -->
      <section class="card">
        <h2>快捷主题</h2>
        <div class="presets" id="quick"></div>
      </section>

      <!-- 灯区 -->
      <section class="card">
        <h2>灯区 <span id="zoneInfo">未选 · 作用于全部</span></h2>
        <div class="zones" id="zones"></div>
        <div class="grid3" style="margin-top:9px">
          <div class="btn" data-sel="all">全选</div>
          <div class="btn" data-sel="keyboard">键盘</div>
          <div class="btn" data-sel="touchpad">触控板</div>
          <div class="btn" data-sel="power">电源键</div>
          <div class="btn" data-sel="clear">清除</div>
        </div>
      </section>

      <!-- 预设 -->
      <section class="card">
        <h2>预设 <span class="muted">点一下即应用</span></h2>
        <div class="presets" id="presets"></div>
      </section>

    </aside>
  </div>

  <div class="foot">
    <span>桌面浏览器和手机页面共用同一套接口：这里的每次改动都会立即下发到机身，Mac 上的操作也会实时回到页面。关掉页面不会关灯。</span>
    <span>AlienMAC · RockJesus</span>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
const $ = (id) => document.getElementById(id);
let state = null;
let dragging = false;

function toast(msg){
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(t._t); t._t = setTimeout(()=>t.classList.remove('show'), 1400);
}

async function act(obj){
  try{
    await fetch('/api/action', {method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify(obj)});
  }catch(e){ toast('连接断了，正在重连…'); }
}

/* ---------- 灯区 ---------- */
function buildZones(zones){
  const box = $('zones'); box.innerHTML = '';
  zones.forEach(z => {
    const el = document.createElement('div');
    el.className = 'zone';
    el.dataset.id = z.id;
    el.innerHTML = '<div class="stripe"></div><span>' + z.name + '</span>';
    el.addEventListener('click', () => {
      el.classList.toggle('sel');
      act({type:'toggleZone', id: z.id});
    });
    box.appendChild(el);
  });
}

/* ---------- 颜色 ---------- */
function buildSwatches(list){
  const box = $('swatches'); box.innerHTML = '';
  list.forEach(item => {
    const el = document.createElement('div');
    el.className = 'sw'; el.dataset.hex = item.hex;
    el.style.background = 'linear-gradient(150deg,' + item.hex + 'ee,' + item.hex + '99)';
    el.title = item.hex;
    el.addEventListener('click', () => {
      $('picker').value = item.hex;
      $('pickerHex').textContent = item.hex.toUpperCase();
      $('mainHex').textContent = item.hex.toUpperCase();
      act({type:'color', hex: item.hex});
    });
    box.appendChild(el);
  });
}

/* ---------- 预设 ---------- */
function presetChip(p, handler){
  const el = document.createElement('div');
  el.className = 'pre';
  el.innerHTML = '<span class="c" style="background:' + p.color + ';color:' + p.color +
                 '"></span><span>' + p.name + '</span>';
  el.addEventListener('click', handler);
  return el;
}

function buildPresets(presets, customs){
  const box = $('presets'); box.innerHTML = '';
  presets.forEach(p => box.appendChild(presetChip(p, () => act({type:'preset', name: p.name}))));
  customs.forEach(c => box.appendChild(presetChip(c, () => act({type:'customPreset', id: c.id}))));
}

const QUICK = ['外星人蓝', '赛博红', '矩阵绿', '极光渐变'];
function buildQuick(presets){
  const box = $('quick'); box.innerHTML = '';
  QUICK.forEach(name => {
    const p = presets.find(x => x.name === name);
    if (p) box.appendChild(presetChip(p, () => act({type:'preset', name: name})));
  });
}

/* ---------- 每区动作 ---------- */
function buildActions(list){
  const box = $('actions'); box.innerHTML = '';
  list.forEach(a => {
    const row = document.createElement('div');
    row.className = 'actRow';
    const loop = a.loop ? '循环' : '单次';
    row.innerHTML = '<span class="c" style="background:' + a.color + ';color:' + a.color + '"></span>' +
                    '<span class="name">' + a.name + '</span>' +
                    '<span class="sum">' + a.summary + '</span>' +
                    '<span class="loop' + (a.loop ? '' : ' off') + '" data-zone="' + a.zone + '">' + loop + '</span>';
    row.querySelector('.loop').addEventListener('click', ev => {
      ev.stopPropagation();
      act({type:'loopAction', zone: a.zone});
    });
    box.appendChild(row);
  });
}

/* ---------- 机身预览 ---------- */
let lastModel = 0;
function refreshModel(){
  const now = Date.now();
  if (now - lastModel < 320) return;
  lastModel = now;
  const img = $('model');
  if (img) img.src = '/api/model.jpg?t=' + now;
}

/* ---------- 状态渲染 ---------- */
function apply(s){
  state = s;

  const sub = s.modelName || (s.subtitle ? s.subtitle.split(' · ')[0] : '');
  if (sub && $('subtitle').textContent !== sub) $('subtitle').textContent = sub;

  const st = $('status');
  st.classList.toggle('off', !s.connected);
  $('statusText').textContent = s.connected ? '已连接' : '未连接';

  if (!dragging){
    $('bri').value = s.brightness;
    $('briText').textContent = s.brightness + '%';
  }

  refreshModel();

  /* 灯区 */
  const zoneEls = [...document.querySelectorAll('.zone')];
  if (zoneEls.length !== s.zones.length) buildZones(s.zones);
  s.zones.forEach(z => {
    const el = document.querySelector('.zone[data-id="' + z.id + '"]');
    if (!el) return;
    el.classList.toggle('sel', z.selected);
    el.querySelector('.stripe').style.background = z.color;
  });
  const selected = s.zones.filter(z => z.selected).length;
  $('zoneInfo').textContent = selected ? ('已选 ' + selected + ' 个') : '未选 · 作用于全部';
  $('zoneCount').textContent = s.zones.length + ' 个灯区';

  /* 颜色 */
  if (!document.querySelector('.sw')) buildSwatches(s.swatches || []);
  $('mainHex').textContent = s.primary.toUpperCase();
  $('mainDot').style.background = s.primary;
  $('mainDot').style.color = s.primary;
  if (document.activeElement !== $('picker')){
    $('picker').value = s.primary;
    $('pickerHex').textContent = s.primary.toUpperCase();
  }
  [...document.querySelectorAll('.sw')].forEach(el =>
    el.classList.toggle('sel', el.dataset.hex.toLowerCase() === s.primary.toLowerCase()));

  /* 效果 */
  [...document.querySelectorAll('[data-eff]')].forEach(el =>
    el.classList.toggle('on', el.dataset.eff === s.effect));
  const needsSpeed = s.effect !== 'color';
  $('tempoWrap').style.display = needsSpeed ? 'block' : 'none';
  if (!dragging){
    $('tempo').value = s.tempo;
    $('tempoText').textContent = s.tempo + ' ms';
  }

  /* 触摸板细调 */
  const t = s.touchpad || {};
  $('swPadFollow').classList.toggle('on', !!t.padFollowsZone);
  $('swEdgeFollow').classList.toggle('on', !!t.edgeFollowsZone);
  $('swEdgeShow').classList.toggle('on', t.edgeEnabled !== false);
  if (document.activeElement !== $('padBri')){
    $('padBri').value = t.padBrightness;
    $('padBriText').textContent = t.padBrightness + '%';
  }
  if (document.activeElement !== $('edgeBri')){
    $('edgeBri').value = t.edgeBrightness;
    $('edgeBriText').textContent = t.edgeBrightness + '%';
  }

  /* 撤销 / 重做 / 关灯 */
  $('btnUndo').classList.toggle('dim', !s.canUndo);
  $('btnCancel').classList.toggle('dim', !s.hasUnappliedEdits);
  $('btnRedo').classList.toggle('dim', !s.canRedo);
  $('btnToggle').textContent = s.lightsOff ? '开灯' : '关灯';

  /* 每区动作 */
  const list = s.zoneActions || [];
  const sig = list.map(a => a.zone + a.loop + a.summary).join('|');
  if (sig !== $('actions').dataset.sig){
    $('actions').dataset.sig = sig;
    buildActions(list);
    $('actionHint').style.display = list.length ? 'none' : 'block';
    $('actionHint').textContent = selected
      ? ('点「＋ 指派」让 ' + selected + ' 个选中灯区各跑自己的效果')
      : '选中灯区后可单独指派效果，让它不再跟随全局';
  }

  /* 预设 */
  const psig = s.presets.length + '|' + s.customPresets.length;
  if (psig !== $('presets').dataset.sig){
    $('presets').dataset.sig = psig;
    buildPresets(s.presets, s.customPresets);
    buildQuick(s.presets);
  }
}

/* ---------- 交互绑定 ---------- */
$('bri').addEventListener('pointerdown', () => dragging = true);
$('bri').addEventListener('pointerup', () => dragging = false);
$('bri').addEventListener('input', () => { $('briText').textContent = $('bri').value + '%'; });
$('bri').addEventListener('change', () => { dragging = false; act({type:'brightness', value: Number($('bri').value)}); });

$('tempo').addEventListener('pointerdown', () => dragging = true);
$('tempo').addEventListener('pointerup', () => dragging = false);
$('tempo').addEventListener('input', () => { $('tempoText').textContent = $('tempo').value + ' ms'; });
$('tempo').addEventListener('change', () => { dragging = false; act({type:'tempo', value: Number($('tempo').value)}); });

$('padBri').addEventListener('input', () => { $('padBriText').textContent = $('padBri').value + '%'; });
$('padBri').addEventListener('change', () => act({type:'touchpad', padBrightness: Number($('padBri').value)}));

$('edgeBri').addEventListener('input', () => { $('edgeBriText').textContent = $('edgeBri').value + '%'; });
$('edgeBri').addEventListener('change', () => act({type:'touchpad', edgeBrightness: Number($('edgeBri').value)}));

$('swPadFollow').addEventListener('click', () => act({type:'touchpad', padFollowsZone: !($('swPadFollow').classList.contains('on'))}));
$('swEdgeFollow').addEventListener('click', () => act({type:'touchpad', edgeFollowsZone: !($('swEdgeFollow').classList.contains('on'))}));
$('swEdgeShow').addEventListener('click', () => act({type:'touchpad', edgeEnabled: !($('swEdgeShow').classList.contains('on'))}));

$('btnPadReset').addEventListener('click', () => act({type:'touchpad', padFollowsZone:true, padBrightness:100,
  edgeFollowsZone:true, edgeEnabled:true, edgeBrightness:100}));

[...document.querySelectorAll('[data-eff]')].forEach(el => {
  el.addEventListener('click', () => act({type:'effect', code: el.dataset.eff}));
});

document.querySelectorAll('[data-sel]').forEach(el => {
  el.addEventListener('click', () => act({type:'select', mode: el.dataset.sel}));
});

$('btnPick').addEventListener('click', () => {
  const row = $('pickerRow');
  row.style.display = row.style.display === 'none' ? 'flex' : 'none';
});
$('picker').addEventListener('input', () => {
  const v = $('picker').value;
  $('pickerHex').textContent = v.toUpperCase();
  $('mainHex').textContent = v.toUpperCase();
  act({type:'color', hex: v});
});
$('btnApplyColor').addEventListener('click', () => act({type:'color', hex: $('picker').value}));

$('btnApply').addEventListener('click', () => { act({type:'apply'}); toast('已应用到选中灯区'); });
$('btnCancel').addEventListener('click', () => { act({type:'cancel'}); toast('已退回上次应用的状态'); });
$('btnUndo').addEventListener('click', () => act({type:'undo'}));
$('btnRedo').addEventListener('click', () => act({type:'redo'}));
$('btnToggle').addEventListener('click', () => act({type:'toggleLights'}));

$('btnAssign').addEventListener('click', () => { act({type:'assignAction'}); toast('已给选中灯区指派动作'); });
$('btnClearActions').addEventListener('click', () => act({type:'clearActions'}));

$('btnSavePreset').addEventListener('click', () => {
  const row = $('saveRow');
  row.style.display = row.style.display === 'none' ? 'flex' : 'none';
  if (row.style.display === 'flex') $('presetName').focus();
});
$('btnSaveOk').addEventListener('click', () => {
  const name = $('presetName').value.trim();
  if (!name) { toast('先起个名字'); return; }
  act({type:'savePreset', name: name});
  $('presetName').value = '';
  $('saveRow').style.display = 'none';
  toast('已保存预设「' + name + '」');
});

document.addEventListener('keydown', e => {
  if (e.key === 'Enter' && document.activeElement === $('presetName')) $('btnSaveOk').click();
});

/* ---------- SSE ---------- */
function connect(){
  const es = new EventSource('/api/events');
  es.addEventListener('state', e => { try { apply(JSON.parse(e.data)); } catch(err) {} });
  es.onopen = () => { $('status').classList.remove('off'); $('statusText').textContent = '已连接'; };
  es.onerror = () => {
    $('status').classList.add('off'); $('statusText').textContent = '重连中';
    es.close(); setTimeout(connect, 1500);
  };
}
connect();
refreshModel();
setInterval(() => { if (!document.hidden) refreshModel(); }, 1600);
</script>
</body>
</html>
"""#
}
