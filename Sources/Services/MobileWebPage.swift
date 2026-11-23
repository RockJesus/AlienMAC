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
.dot{width:32px;height:32px;border-radius:10px;display:grid;place-items:center;flex:none;
  background:linear-gradient(145deg,#0af,#a4f);box-shadow:0 0 18px rgba(0,180,255,.45)}
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
.toast{position:fixed;left:50%;bottom:calc(24px + env(safe-area-inset-bottom));
  transform:translate(-50%,20px);background:rgba(10,18,30,.94);
  border:1px solid rgba(0,190,255,.5);color:#dff3ff;padding:9px 15px;border-radius:999px;
  font-size:13px;opacity:0;pointer-events:none;transition:.25s;
  box-shadow:0 8px 26px rgba(0,0,0,.5);z-index:9;white-space:nowrap}
.toast.show{opacity:1;transform:translate(-50%,0)}
</style>
</head>
<body>

<div class="head">
  <div class="dot"><svg viewBox="0 0 24 24"><path d="M12 2 3 20h5.2l1.9-4.1h3.8L16 20H21L12 2z"/></svg></div>
  <div class="tt"><h1>AlienMAC</h1><p id="subtitle">正在连接…</p></div>
  <div class="pill" id="status"><i></i><b id="statusText">连接中</b></div>
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
  <h2>预设</h2>
  <div class="grid presets" id="presets"></div>
</div>

<p class="tip">手机上的每一次改动都会立即同步到 Mac 和机身灯光，Mac 上的操作也会实时回到这里。离开这个页面不会关灯。</p>

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

function apply(s){
  state = s;
  if (s.subtitle && $('subtitle').textContent !== s.subtitle) $('subtitle').textContent = s.subtitle;

  const st = $('status');
  st.classList.toggle('off', !s.connected);
  $('statusText').textContent = s.connected ? '已连接' : '未连接';

  if (!dragging){
    $('bri').value = s.brightness;
    $('briText').textContent = s.brightness + '%';
  }
  $('btnOn').classList.toggle('on', !s.lightsOff);
  $('btnOff').classList.toggle('on', s.lightsOff);

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
</script>
</body>
</html>
"""#
}
