//
//  DesktopWebPage.swift
//  AlienMAC
//
//  桌面端控制页面（浏览器打开，和手机版共用同一套 HTTP / SSE 接口）
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
<style>
*{box-sizing:border-box}
html,body{margin:0;padding:0;background:#04070c;color:#e6ecf5;
  font:14px/1.5 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif}
body{min-height:100vh;
  background:
    radial-gradient(120% 90% at 22% 18%, #0a1c30 0%, #05080f 55%, #000 100%),
    radial-gradient(70% 60% at 92% 8%, rgba(140,50,230,.16), transparent 60%);}
a{color:inherit;text-decoration:none}
.shell{max-width:1240px;margin:0 auto;padding:22px 24px 28px}

/* 顶栏 */
.bar{display:flex;align-items:center;gap:14px;margin-bottom:16px}
.mark{width:40px;height:40px;border-radius:12px;flex:none;display:grid;place-items:center;
  background:linear-gradient(145deg,#0af,#a4f);box-shadow:0 0 22px rgba(0,180,255,.4)}
.mark svg{width:22px;height:22px;fill:#fff;opacity:.95}
.bar h1{margin:0;font-size:19px;font-weight:650;letter-spacing:.3px}
.bar p{margin:1px 0 0;font-size:11.5px;color:#8ba0bb}
.bar .push{margin-left:auto;display:flex;align-items:center;gap:10px}
.pill{display:flex;align-items:center;gap:7px;padding:7px 13px;border-radius:999px;font-size:12px;
  background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);color:#c2cfdf;white-space:nowrap}
.pill i{width:7px;height:7px;border-radius:50%;background:#31e58a;box-shadow:0 0 9px #31e58a}
.pill.off i{background:#ff5a5a;box-shadow:0 0 9px #ff5a5a}
.link{padding:7px 13px;border-radius:999px;font-size:12px;color:#9fb4cc;
  border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.04);transition:.15s}
.link:hover{color:#fff;border-color:rgba(0,200,255,.6);background:rgba(0,170,255,.12)}

/* 布局 */
.main{display:grid;grid-template-columns:minmax(0,1fr) 392px;gap:16px;align-items:start}
.card{background:rgba(255,255,255,.052);border:1px solid rgba(255,255,255,.1);
  border-radius:18px;padding:15px;backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px)}
.card h2{margin:0 0 11px;font-size:12px;font-weight:600;letter-spacing:.7px;text-transform:uppercase;
  color:#93a3bb;display:flex;align-items:center;justify-content:space-between;gap:10px}
.card h2 span{font:12px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:#7ad9ff;
  text-transform:none;letter-spacing:0}

/* 机身预览 */
.stage{padding:16px 16px 12px;display:flex;flex-direction:column;gap:10px;position:sticky;top:16px}
.stage img{display:block;width:100%;border-radius:14px;background:#04070c;
  border:1px solid rgba(255,255,255,.07)}
.stage .foot{display:flex;align-items:center;gap:10px;font-size:11.5px;color:#7e8fa6;line-height:1.6}
.stage .foot b{color:#a9bdd4;font-weight:500}

/* 控制器 */
.side{display:flex;flex-direction:column;gap:14px}
.row{display:flex;align-items:center;gap:8px}
.btn{border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.055);color:#dfe8f5;
  border-radius:11px;padding:9px 12px;font-size:13px;font-weight:520;flex:1;text-align:center;
  transition:.15s;cursor:pointer;user-select:none;min-width:0;white-space:nowrap;
  overflow:hidden;text-overflow:ellipsis}
.btn:hover{background:rgba(255,255,255,.1)}
.btn:active{transform:scale(.985)}
.btn.on{border-color:rgba(0,190,255,.75);background:rgba(0,170,255,.17);color:#fff;
  box-shadow:inset 0 0 18px rgba(0,170,255,.22)}

/* 亮度 */
.slider{display:flex;align-items:center;gap:12px}
input[type=range]{-webkit-appearance:none;appearance:none;flex:1;height:26px;background:transparent;margin:0}
input[type=range]::-webkit-slider-runnable-track{height:8px;border-radius:6px;
  background:linear-gradient(90deg,#00c2ff,#7a5cff)}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:20px;height:20px;border-radius:50%;
  margin-top:-6px;background:#fff;box-shadow:0 0 12px rgba(0,190,255,.85);border:0;cursor:pointer}
input[type=range]::-moz-range-track{height:8px;border-radius:6px;background:linear-gradient(90deg,#00c2ff,#7a5cff)}
input[type=range]::-moz-range-thumb{width:20px;height:20px;border:0;border-radius:50%;background:#fff}

/* 灯区 */
.zones{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
.zone{position:relative;border:1px solid rgba(255,255,255,.1);background:rgba(255,255,255,.04);
  border-radius:11px;padding:11px 6px 8px;font-size:12px;color:#a9b7cc;text-align:center;
  overflow:hidden;transition:.15s;cursor:pointer}
.zone span{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.zone .bar{position:absolute;left:0;right:0;top:0;height:3px;filter:saturate(1.3)}
.zone:hover{background:rgba(255,255,255,.09)}
.zone.sel{color:#fff;border-color:rgba(0,195,255,.8);background:rgba(0,170,255,.16);
  box-shadow:0 0 16px rgba(0,170,255,.22)}

/* 颜色 */
.swatches{display:grid;grid-template-columns:repeat(8,1fr);gap:8px}
.sw{height:40px;border-radius:11px;border:1px solid rgba(255,255,255,.16);cursor:pointer;transition:.15s}
.sw:hover{transform:translateY(-1px)}
.sw.sel{outline:2px solid #fff;outline-offset:2px}
.pickerRow{display:flex;align-items:center;gap:10px;margin-top:11px}
.pickerRow input[type=color]{width:46px;height:36px;border:1px solid rgba(255,255,255,.18);
  border-radius:11px;background:transparent;padding:2px;cursor:pointer}
.hex{font:13px/1 ui-monospace,SFMono-Regular,Menlo,monospace;color:#8ea1bb}

/* 效果 */
.effects{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}

/* 预设 */
.presets{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
.pre{display:flex;align-items:center;gap:9px;border:1px solid rgba(255,255,255,.1);
  background:rgba(255,255,255,.04);border-radius:11px;padding:9px 10px;font-size:13px;
  color:#ccd8e8;cursor:pointer;transition:.15s}
.pre:hover{background:rgba(255,255,255,.09)}
.pre .c{width:11px;height:11px;border-radius:50%;flex:none;box-shadow:0 0 10px currentColor}

.foot{display:flex;justify-content:space-between;gap:14px;margin-top:16px;
  font-size:11.5px;color:#6f8098;line-height:1.6}
.toast{position:fixed;left:50%;bottom:26px;transform:translate(-50%,16px);
  background:rgba(10,18,30,.95);border:1px solid rgba(0,190,255,.5);color:#dff3ff;
  padding:9px 16px;border-radius:999px;font-size:13px;opacity:0;pointer-events:none;
  transition:.25s;box-shadow:0 10px 28px rgba(0,0,0,.5);z-index:9;white-space:nowrap}
.toast.show{opacity:1;transform:translate(-50%,0)}

@media (max-width:1040px){
  .main{grid-template-columns:minmax(0,1fr)}
  .stage{position:static}
  .shell{padding:16px}
}
</style>
</head>
<body>
<div class="shell">

  <div class="bar">
    <div class="mark"><svg viewBox="0 0 24 24"><path d="M12 2 3 20h5.2l1.9-4.1h3.8L16 20H21L12 2z"/></svg></div>
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
      <section class="card">
        <h2>亮度 <span id="briText">100%</span></h2>
        <div class="slider">
          <input id="bri" type="range" min="0" max="100" step="1" value="100">
        </div>
        <div class="row" style="margin-top:11px">
          <div class="btn" id="btnOn">开灯</div>
          <div class="btn" id="btnOff">关灯</div>
        </div>
      </section>

      <section class="card">
        <h2>灯区 <span id="zoneInfo">未选 · 作用于全部</span></h2>
        <div class="zones" id="zones"></div>
        <div class="row" style="margin-top:9px">
          <div class="btn" data-sel="all">全选</div>
          <div class="btn" data-sel="keyboard">键盘</div>
          <div class="btn" data-sel="touchpad">触控板</div>
          <div class="btn" data-sel="clear">清除</div>
        </div>
      </section>

      <section class="card">
        <h2>颜色 <span id="colorHex">#0080FF</span></h2>
        <div class="swatches" id="swatches"></div>
        <div class="pickerRow">
          <input id="picker" type="color" value="#0080ff">
          <div class="hex" id="pickerHex">#0080FF</div>
          <div class="btn" id="btnApply" style="flex:none;padding:9px 18px">应用</div>
        </div>
      </section>

      <section class="card">
        <h2>效果 <span id="effectName">常亮</span></h2>
        <div class="effects" id="effects"></div>
        <div id="tempoWrap" style="margin-top:12px;display:none">
          <h2 style="margin:0 0 2px">速度 <span id="tempoText">2000 ms</span></h2>
          <div class="slider"><input id="tempo" type="range" min="500" max="8000" step="250" value="2000"></div>
        </div>
      </section>

      <section class="card">
        <h2>预设</h2>
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
let lastCustom = [];

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
    el.title = item.hex;
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

let lastModel = 0;
function refreshModel(){
  const now = Date.now();
  if (now - lastModel < 320) return;
  lastModel = now;
  const img = $('model');
  if (img) img.src = '/api/model.jpg?t=' + now;
}

function apply(s){
  state = s;
  if (s.subtitle){
    const sub = s.subtitle.replace('手机遥控', '桌面遥控');
    if ($('subtitle').textContent !== sub) $('subtitle').textContent = sub;
  }

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

  const zoneEls = [...document.querySelectorAll('.zone')];
  if (zoneEls.length !== s.zones.length) buildZones(s.zones);
  s.zones.forEach(z => {
    const el = document.querySelector('.zone[data-id="' + z.id + '"]');
    if (!el) return;
    el.classList.toggle('sel', z.selected);
    el.querySelector('.bar').style.background = z.color;
  });
  const selected = s.zones.filter(z => z.selected).length;
  $('zoneInfo').textContent = selected ? ('已选 ' + selected + ' 个') : '未选 · 作用于全部';

  if (!document.querySelector('.sw')) buildSwatches(s.swatches || []);
  $('colorHex').textContent = s.primary.toUpperCase();
  if (document.activeElement !== $('picker')){
    $('picker').value = s.primary;
    $('pickerHex').textContent = s.primary.toUpperCase();
  }
  [...document.querySelectorAll('.sw')].forEach(el =>
    el.classList.toggle('sel', el.dataset.hex.toLowerCase() === s.primary.toLowerCase()));

  if (!document.querySelector('#effects .btn')) buildEffects(s.effects);
  $('effectName').textContent = s.effectName;
  [...document.querySelectorAll('#effects .btn')].forEach(el =>
    el.classList.toggle('on', el.dataset.code === s.effect));

  $('tempoWrap').style.display = s.needsSecondary ? 'block' : 'none';
  if (!dragging){
    $('tempo').value = s.tempo;
    $('tempoText').textContent = s.tempo + ' ms';
  }

  const sig = s.presets.length + '|' + s.customPresets.length;
  if (sig !== $('presets').dataset.sig){
    $('presets').dataset.sig = sig;
    buildPresets(s.presets, s.customPresets);
    lastCustom = s.customPresets;
  }
}

$('bri').addEventListener('pointerdown', () => dragging = true);
$('bri').addEventListener('pointerup', () => dragging = false);
$('bri').addEventListener('input', () => { $('briText').textContent = $('bri').value + '%'; });
$('bri').addEventListener('change', () => { dragging = false; act({type:'brightness', value: Number($('bri').value)}); });

$('tempo').addEventListener('pointerdown', () => dragging = true);
$('tempo').addEventListener('pointerup', () => dragging = false);
$('tempo').addEventListener('input', () => { $('tempoText').textContent = $('tempo').value + ' ms'; });
$('tempo').addEventListener('change', () => { dragging = false; act({type:'tempo', value: Number($('tempo').value)}); });

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
