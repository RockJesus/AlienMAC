//
//  MobileWebPage.swift
//  AlienMAC
//
//  手机端控制页面（由内置 WebBridge 直接返回，无需联网、无需装 App）
//

import Foundation

enum MobileWebPage {

    static let html = #"""
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, maximum-scale=1">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="theme-color" content="#05080f">
<title>AlienMAC</title>
<link rel="icon" href="/api/logo.png">
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;padding:0;background:#05080f;color:#e8eef7;
  font:15px/1.45 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif}
body{overflow-x:hidden;min-height:100vh;padding:calc(14px + env(safe-area-inset-top)) 14px calc(24px + env(safe-area-inset-bottom));
  background:
    radial-gradient(120% 60% at 15% 0%, rgba(0,150,255,.20), transparent 60%),
    radial-gradient(100% 50% at 100% 10%, rgba(150,60,255,.16), transparent 60%),
    #05080f;
  max-width:560px;margin:0 auto}
.head{display:flex;align-items:center;gap:10px;margin:4px 2px 14px}
.dot{height:34px;width:auto;flex:none;display:block;
  filter:drop-shadow(0 0 10px rgba(0,190,255,.45)}
.dot svg{width:19px;height:19px;fill:#fff;opacity:.95}
.tt{flex:1;min-width:0}
.tt h1{margin:0;font-size:19px;font-weight:650;letter-spacing:.2px}
.tt p{margin:0;font-size:11.5px;color:#8b9bb4}
.pill{display:flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;font-size:12px;
  background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.11);color:#bfcbdd;white-space:nowrap}
.pill i{width:7px;height:7px;border-radius:50%;background:#31e58a;box-shadow:0 0 8px #31e58a}
.pill.off i{background:#ff5a5a;box-shadow:0 0 8px #ff5a5a}
.card{background:rgba(255,255,255,.055);border:1px solid rgba(255,255,255,.10);border-radius:16px;
  padding:13px;margin-bottom:11px;backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px)}
.card h2{margin:0 0 10px;font-size:12px;font-weight:600;letter-spacing:.6px;text-transform:uppercase;
  color:#93a3bb;display:flex;justify-content:space-between;align-items:center}
.card h2 span{font:12px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:#7ad9ff;
  text-transform:none;letter-spacing:0}
.row{display:flex;align-items:center;gap:9px}
.btn{border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#dfe8f5;
  border-radius:11px;padding:9px 8px;font-size:13.5px;font-weight:520;flex:1;text-align:center;
  transition:.15s;cursor:pointer;user-select:none;min-width:0;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.btn:active{transform:scale(.97);background:rgba(255,255,255,.12)}
.btn.on{border-color:rgba(0,190,255,.7);background:rgba(0,170,255,.18);color:#fff;
  box-shadow:inset 0 0 16px rgba(0,170,255,.22)}
.grid{display:grid;gap:8px;min-width:0}
.zones{grid-template-columns:repeat(3,minmax(0,1fr))}
.zone{position:relative;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.04);
  border-radius:12px;padding:10px 6px 8px;font-size:12px;color:#a9b7cc;text-align:center;
  overflow:hidden;transition:.16s;cursor:pointer;min-width:0}
.zone span{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.zone .bar{position:absolute;left:0;right:0;top:0;height:3px;opacity:.9;filter:saturate(1.25)}
.zone.sel{color:#fff;border-color:rgba(0,195,255,.75);background:rgba(0,170,255,.16);
  box-shadow:0 0 16px rgba(0,170,255,.25)}
.zone:active{transform:scale(.97)}
.effects{grid-template-columns:repeat(4,minmax(0,1fr))}
.sw{position:relative;height:44px;border-radius:12px;border:1px solid rgba(255,255,255,.16);
  cursor:pointer;overflow:hidden}
.sw.sel{outline:2px solid #fff;outline-offset:2px}
input[type=range]{-webkit-appearance:none;width:100%;height:26px;background:transparent;margin:0}
input[type=range]::-webkit-slider-runnable-track{height:8px;border-radius:6px;
  background:linear-gradient(90deg,#00c2ff,#7a5cff)}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:24px;height:24px;border-radius:50%;
  margin-top:-8px;background:#fff;box-shadow:0 0 12px rgba(0,190,255,.8);border:0}
.colorrow{display:flex;gap:10px;align-items:center;margin-top:10px}
.colorrow input[type=color]{width:46px;height:38px;border:1px solid rgba(255,255,255,.18);
  border-radius:11px;background:transparent;padding:2px}
.colorrow .hex{font:13px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:#8ea1bb}
.tip{font-size:11.5px;color:#77869c;margin:2px 4px 0;line-height:1.55}
.presets{grid-template-columns:repeat(2,minmax(0,1fr))}
.pre{display:flex;align-items:center;gap:9px;border:1px solid rgba(255,255,255,.10);
  background:rgba(255,255,255,.04);border-radius:12px;padding:9px 10px;font-size:13px;
  color:#ccd8e8;cursor:pointer}
.pre .c{width:12px;height:12px;border-radius:50%;flex:none;box-shadow:0 0 10px currentColor}
.pre:active{transform:scale(.98)}
img#model{display:block;width:100%;border-radius:13px;background:#04070c;
  border:1px solid rgba(255,255,255,.08);min-height:120px}
.toast{position:fixed;left:50%;bottom:calc(24px + env(safe-area-inset-bottom));
  transform:translate(-50%,20px);background:rgba(10,18,30,.94);
  border:1px solid rgba(0,190,255,.5);color:#dff3ff;padding:9px 15px;border-radius:999px;
  font-size:13px;opacity:0;pointer-events:none;transition:.25s;
  box-shadow:0 8px 26px rgba(0,0,0,.5);z-index:9;white-space:nowrap}
.toast.show{opacity:1;transform:translate(-50%,0)}
.sw-line{display:flex;align-items:center;gap:9px;padding:6px 0;font-size:13px;color:#cfdbeb}
.switch{width:40px;height:23px;border-radius:999px;flex:none;position:relative;cursor:pointer;
  background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.14);transition:.18s}
.switch b{position:absolute;top:2px;left:2px;width:17px;height:17px;border-radius:50%;
  background:#cfd9e6;transition:.18s}
.switch.on{background:rgba(0,190,255,.55);border-color:rgba(0,190,255,.7);
  box-shadow:0 0 12px rgba(0,180,255,.35)}
.switch.on b{left:19px;background:#fff}
.valLabel{font:12px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:#8ea1bb;margin-left:auto}
.actions{display:flex;flex-direction:column;gap:6px}
.actRow{display:flex;align-items:center;gap:8px;padding:7px 9px;border-radius:11px;
  background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08)}
.actRow .c{width:9px;height:9px;border-radius:50%;flex:none;box-shadow:0 0 8px currentColor}
.actRow .name{font-size:12.5px;color:#d5e1ef;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:84px}
.actRow .sum{font-size:11.5px;color:#8295ad;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1}
.actRow .loop{font-size:11.5px;color:#7ad9ff;padding:3px 8px;border-radius:8px;
  border:1px solid rgba(0,190,255,.3);background:rgba(0,190,255,.08)}
.actRow .loop.off{color:#8ba0bb;border-color:rgba(255,255,255,.14);background:transparent}
.saveRow{display:flex;gap:8px;margin-top:9px;align-items:center}
.saveRow input{flex:1;min-width:0;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.14);
  border-radius:11px;color:#e6ecf5;font-size:13px;padding:9px 11px;outline:none}
.saveRow .btn{flex:none;padding:9px 15px}
</style>
</head>
<body>

<div class="head">
  <img class="dot" src="/api/logo.png" alt="AlienMAC">
  <div class="tt"><h1>AlienMAC</h1><p id="subtitle">正在连接…</p></div>
  <div class="pill" id="status"><i></i><b id="statusText">连接中</b></div>
</div>

<div class="card">
  <h2>机身预览 <span id="modelHint">与 Mac 同步</span></h2>
  <img id="model" alt="AlienMAC">
</div>

<div class="card">
  <h2>亮度 <span id="briText">100%</span></h2>
  <input id="bri" type="range" min="0" max="100" step="1" value="100">
  <div class="row" style="margin-top:10px">
    <div class="btn" id="btnOn">开灯</div>
    <div class="btn" id="btnOff">关灯</div>
  </div>
</div>

<div class="card">
  <h2>灯区 <span id="zoneInfo">未选 · 作用于全部</span></h2>
  <div class="grid zones" id="zones"></div>
  <div class="row" style="margin-top:9px">
    <div class="btn" data-sel="all">全选</div>
    <div class="btn" data-sel="keyboard">键盘</div>
    <div class="btn" data-sel="touchpad">触控板</div>
    <div class="btn" data-sel="clear">清除</div>
  </div>
</div>

<div class="card">
  <h2>颜色 <span id="colorHex">#0080FF</span></h2>
  <div class="grid" id="swatches" style="grid-template-columns:repeat(6,1fr)"></div>
  <div class="colorrow">
    <input id="picker" type="color" value="#0080ff">
    <div class="hex" id="pickerHex">#0080FF</div>
    <div class="btn" id="btnApply" style="flex:none;padding:9px 14px">应用</div>
  </div>
</div>

<div class="card">
  <h2>效果 <span id="effectName">常亮</span></h2>
  <div class="grid effects" id="effects"></div>
  <div id="tempoWrap" style="margin-top:10px;display:none">
    <h2 style="margin:2px 0 4px">速度 <span id="tempoText">2000 ms</span></h2>
    <input id="tempo" type="range" min="500" max="8000" step="250" value="2000">
  </div>
</div>

<div class="card">
  <h2>触摸板细调 <span id="padReset" style="cursor:pointer">恢复默认</span></h2>
  <div class="sw-line">
    <div class="switch" id="swPadFollow"><b></b></div>
    <div>整面背光跟随灯区色</div>
  </div>
  <input id="padBri" type="range" min="0" max="100" step="1" value="100">
  <div class="sw-line"><div>整面亮度</div><div class="valLabel" id="padBriText">100%</div></div>
  <div class="sw-line">
    <div class="switch" id="swEdgeFollow"><b></b></div>
    <div>边光跟随灯区色</div>
  </div>
  <div class="sw-line">
    <div class="switch" id="swEdgeShow"><b></b></div>
    <div>显示边光</div>
  </div>
  <input id="edgeBri" type="range" min="0" max="100" step="1" value="100">
  <div class="sw-line"><div>边光强度</div><div class="valLabel" id="edgeBriText">100%</div></div>
</div>

<div class="card">
  <h2>快捷操作</h2>
  <div class="row">
    <div class="btn" id="btnUndo">撤销</div>
    <div class="btn" id="btnRedo">重做</div>
    <div class="btn" id="btnCancel">取消改动</div>
  </div>
</div>

<div class="card">
  <h2>每区动作 <span style="display:flex;gap:14px;align-items:center">
    <a id="btnClearActions" style="color:#8295ad">清空</a>
    <a id="btnAssign" style="color:#7ad9ff">＋ 指派</a></span></h2>
  <p class="tip" id="actionHint" style="margin:0 0 8px">选中灯区后可单独指派效果，让它不再跟随全局</p>
  <div class="actions" id="actions"></div>
  <div class="row" style="margin-top:10px">
    <div class="btn" id="btnSavePreset">存为预设</div>
  </div>
  <div class="saveRow" id="saveRow" style="display:none">
    <input id="presetName" placeholder="预设名称" enterkeyhint="done">
    <div class="btn" id="btnSaveOk">保存</div>
  </div>
</div>

<div class="card">
  <h2>快捷主题</h2>
  <div class="grid presets" id="quick"></div>
</div>

<div class="card">
  <h2>预设</h2>
  <div class="grid presets" id="presets"></div>
</div>

<p class="tip">手机上的每一次改动都会立即同步到 Mac 和机身灯光，Mac 上的操作也会实时回到这里。离开这个页面不会关灯。<br><a href="/desktop" style="color:#7ad9ff">在电脑上打开桌面版 ›</a></p>

<div class="toast" id="toast"></div>

<script>
const $ = (id) => document.getElementById(id);
let state = null;
let dragging = false;
let lastCustom = [];

function hexToRgb(hex){
  const h = (hex||'#000000').replace('#','');
  return parseInt(h.substring(0,2),16)+','+parseInt(h.substring(2,4),16)+','+parseInt(h.substring(4,6),16);
}

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

// ---------- 渲染 ----------
function buildZones(zones){
  const box = $('zones'); box.innerHTML = '';
  zones.forEach(z => {
    const el = document.createElement('div');
    el.className = 'zone';
    el.dataset.id = z.id;
    el.innerHTML = '<div class="bar"></div><span>' + z.name + '</span>';
    el.addEventListener('click', () => {
      el.classList.toggle('sel');
      act({type:'toggleZone', id: z.id});
    });
    box.appendChild(el);
  });
}

function buildEffects(effects){
  const box = $('effects'); box.innerHTML = '';
  effects.forEach(e => {
    const el = document.createElement('div');
    el.className = 'btn'; el.dataset.code = e.code; el.textContent = e.name;
    el.addEventListener('click', () => {
      [...box.children].forEach(c => c.classList.remove('on'));
      el.classList.add('on');
      act({type:'effect', code: e.code});
    });
    box.appendChild(el);
  });
}

function buildSwatches(list){
  const box = $('swatches'); box.innerHTML = '';
  list.forEach(item => {
    const el = document.createElement('div');
    el.className = 'sw'; el.dataset.hex = item.hex;
    el.style.background = 'linear-gradient(150deg,' + item.hex + 'ee,' + item.hex + '99)';
    el.addEventListener('click', () => {
      $('picker').value = item.hex;
      $('pickerHex').textContent = item.hex.toUpperCase();
      $('colorHex').textContent = item.hex.toUpperCase();
      act({type:'color', hex: item.hex});
    });
    box.appendChild(el);
  });
}

function buildPresets(presets, customs){
  const box = $('presets'); box.innerHTML = '';
  presets.forEach(p => {
    const el = document.createElement('div');
    el.className = 'pre';
    el.innerHTML = '<span class="c" style="background:' + p.color + ';color:' + p.color + '"></span><span>' + p.name + '</span>';
    el.addEventListener('click', () => act({type:'preset', name: p.name}));
    box.appendChild(el);
  });
  customs.forEach(c => {
    const el = document.createElement('div');
    el.className = 'pre';
    el.innerHTML = '<span class="c" style="background:' + c.color + ';color:' + c.color + '"></span><span>' + c.name + '</span>';
    el.addEventListener('click', () => act({type:'customPreset', id: c.id}));
    box.appendChild(el);
  });
}

const QUICK = ['外星人蓝', '赛博红', '矩阵绿', '极光渐变'];

function buildQuick(presets){
  const box = $('quick'); box.innerHTML = '';
  QUICK.forEach(name => {
    const p = presets.find(x => x.name === name);
    if (!p) return;
    const el = document.createElement('div');
    el.className = 'pre';
    el.innerHTML = '<span class="c" style="background:' + p.color + ';color:' + p.color + '"></span><span>' + p.name + '</span>';
    el.addEventListener('click', () => act({type:'preset', name: name}));
    box.appendChild(el);
  });
}

function buildActions(list){
  const box = $('actions'); box.innerHTML = '';
  list.forEach(a => {
    const row = document.createElement('div');
    row.className = 'actRow';
    row.innerHTML = '<span class="c" style="background:' + a.color + ';color:' + a.color + '"></span>' +
                    '<span class="name">' + a.name + '</span>' +
                    '<span class="sum">' + a.summary + '</span>' +
                    '<span class="loop' + (a.loop ? '' : ' off') + '">' + (a.loop ? '循环' : '单次') + '</span>';
    row.querySelector('.loop').addEventListener('click', ev => {
      ev.stopPropagation();
      act({type:'loopAction', zone: a.zone});
    });
    box.appendChild(row);
  });
}

let lastModel = 0;
function refreshModel(){
  const now = Date.now();
  if (now - lastModel < 350) return;
  lastModel = now;
  const img = $('model');
  if (img) img.src = '/api/model.jpg?t=' + now;
}

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
  $('btnOn').classList.toggle('on', !s.lightsOff);
  $('btnOff').classList.toggle('on', s.lightsOff);

  refreshModel();

  // 灯区
  const zoneEls = [...document.querySelectorAll('.zone')];
  if (zoneEls.length !== s.zones.length) buildZones(s.zones);
  s.zones.forEach((z, i) => {
    const el = document.querySelector('.zone[data-id="' + z.id + '"]');
    if (!el) return;
    el.classList.toggle('sel', z.selected);
    el.querySelector('.bar').style.background = z.color;
  });
  const selected = s.zones.filter(z => z.selected).length;
  $('zoneInfo').textContent = selected ? ('已选 ' + selected + ' 个') : '未选 · 作用于全部';

  // 颜色
  if (!document.querySelector('.sw')) buildSwatches(s.swatches || []);
  $('colorHex').textContent = s.primary.toUpperCase();
  if (document.activeElement !== $('picker')){
    $('picker').value = s.primary;
    $('pickerHex').textContent = s.primary.toUpperCase();
  }
  [...document.querySelectorAll('.sw')].forEach(el =>
    el.classList.toggle('sel', el.dataset.hex.toLowerCase() === s.primary.toLowerCase()));

  // 效果
  if (!document.querySelector('#effects .btn')){
    buildEffects(s.effects);
  }
  $('effectName').textContent = s.effectName;
  [...document.querySelectorAll('#effects .btn')].forEach(el =>
    el.classList.toggle('on', el.dataset.code === s.effect));

  $('tempoWrap').style.display = s.needsSecondary ? 'block' : 'none';
  if (!dragging){
    $('tempo').value = s.tempo;
    $('tempoText').textContent = s.tempo + ' ms';
  }

  // 预设
  const sig = s.presets.length + '|' + s.customPresets.length;
  if (sig !== $('presets').dataset.sig){
    $('presets').dataset.sig = sig;
    buildPresets(s.presets, s.customPresets);
  }
  if (lastCustom.length !== s.customPresets.length){
    lastCustom = s.customPresets;
    buildPresets(s.presets, s.customPresets);
  }

  // 触摸板细调
  const tp = s.touchpad || {};
  $('swPadFollow').classList.toggle('on', !!tp.padFollowsZone);
  $('swEdgeFollow').classList.toggle('on', !!tp.edgeFollowsZone);
  $('swEdgeShow').classList.toggle('on', tp.edgeEnabled !== false);
  if (document.activeElement !== $('padBri')){
    $('padBri').value = tp.padBrightness;
    $('padBriText').textContent = tp.padBrightness + '%';
  }
  if (document.activeElement !== $('edgeBri')){
    $('edgeBri').value = tp.edgeBrightness;
    $('edgeBriText').textContent = tp.edgeBrightness + '%';
  }

  // 撤销 / 重做 / 取消
  $('btnUndo').style.opacity = s.canUndo ? 1 : .45;
  $('btnRedo').style.opacity = s.canRedo ? 1 : .45;
  $('btnCancel').style.opacity = s.hasUnappliedEdits ? 1 : .45;

  // 每区动作
  const list = s.zoneActions || [];
  const asig = list.map(a => a.zone + a.loop + a.summary).join('|');
  if (asig !== $('actions').dataset.sig){
    $('actions').dataset.sig = asig;
    buildActions(list);
    $('actionHint').style.display = list.length ? 'none' : 'block';
    $('actionHint').textContent = selected
      ? ('点「＋ 指派」让 ' + selected + ' 个选中灯区各跑自己的效果')
      : '选中灯区后可单独指派效果，让它不再跟随全局';
  }

  // 快捷主题
  if (sig !== $('quick').dataset.sig){
    $('quick').dataset.sig = sig;
    buildQuick(s.presets);
  }
}

// ---------- 交互 ----------
$('bri').addEventListener('pointerdown', () => dragging = true);
$('bri').addEventListener('pointerup', () => dragging = false);
$('bri').addEventListener('input', () => {
  $('briText').textContent = $('bri').value + '%';
});
$('bri').addEventListener('change', () => {
  dragging = false;
  act({type:'brightness', value: Number($('bri').value)});
});

$('tempo').addEventListener('pointerdown', () => dragging = true);
$('tempo').addEventListener('pointerup', () => dragging = false);
$('tempo').addEventListener('input', () => { $('tempoText').textContent = $('tempo').value + ' ms'; });
$('tempo').addEventListener('change', () => {
  dragging = false;
  act({type:'tempo', value: Number($('tempo').value)});
});

$('btnOn').addEventListener('click', () => { if (state && state.lightsOff) act({type:'toggleLights'}); });
$('btnOff').addEventListener('click', () => { if (state && !state.lightsOff) act({type:'toggleLights'}); });

document.querySelectorAll('[data-sel]').forEach(el => {
  el.addEventListener('click', () => act({type:'select', mode: el.dataset.sel}));
});

$('picker').addEventListener('input', () => {
  const v = $('picker').value;
  $('pickerHex').textContent = v.toUpperCase();
  $('colorHex').textContent = v.toUpperCase();
  act({type:'color', hex: v});
});
$('btnApply').addEventListener('click', () => { act({type:'apply'}); toast('已应用到选中灯区'); });

$('padBri').addEventListener('input', () => { $('padBriText').textContent = $('padBri').value + '%'; });
$('padBri').addEventListener('change', () => act({type:'touchpad', padBrightness: Number($('padBri').value)}));
$('edgeBri').addEventListener('input', () => { $('edgeBriText').textContent = $('edgeBri').value + '%'; });
$('edgeBri').addEventListener('change', () => act({type:'touchpad', edgeBrightness: Number($('edgeBri').value)}));
$('swPadFollow').addEventListener('click', () => act({type:'touchpad', padFollowsZone: !$('swPadFollow').classList.contains('on')}));
$('swEdgeFollow').addEventListener('click', () => act({type:'touchpad', edgeFollowsZone: !$('swEdgeFollow').classList.contains('on')}));
$('swEdgeShow').addEventListener('click', () => act({type:'touchpad', edgeEnabled: !$('swEdgeShow').classList.contains('on')}));
$('padReset').addEventListener('click', () => act({type:'touchpad', padFollowsZone:true, padBrightness:100,
  edgeFollowsZone:true, edgeEnabled:true, edgeBrightness:100}));

$('btnUndo').addEventListener('click', () => act({type:'undo'}));
$('btnRedo').addEventListener('click', () => act({type:'redo'}));
$('btnCancel').addEventListener('click', () => { act({type:'cancel'}); toast('已退回上次应用的状态'); });

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

// ---------- 实时同步 ----------
function connect(){
  const es = new EventSource('/api/events');
  es.addEventListener('state', e => {
    try { apply(JSON.parse(e.data)); } catch(err) {}
  });
  es.onopen = () => { $('status').classList.remove('off'); $('statusText').textContent = '已连接'; };
  es.onerror = () => {
    $('status').classList.add('off'); $('statusText').textContent = '重连中';
    es.close(); setTimeout(connect, 1500);
  };
}
connect();
refreshModel();
setInterval(() => { if (!document.hidden) refreshModel(); }, 2000);
</script>
</body>
</html>
"""#
}
