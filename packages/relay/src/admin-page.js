/**
 * The operator dashboard: a self-contained read-only page served at /admin when
 * ADMIN_SECRET is configured. It holds no secret of its own — the operator types
 * it in, it lives only in the tab's sessionStorage, and it is sent as a bearer
 * token to /api/admin/summary. Inline CSS + vanilla JS + inline-SVG sparklines,
 * with no external loads, so it works unchanged on either backend.
 *
 * Authored template-literal-free (no backticks, no ${...}) so the whole document
 * can be embedded in one outer template literal without escaping.
 */
export const ADMIN_PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex" />
<title>Partage relay — operator</title>
<style>
:root{--bg:#0f1115;--panel:#171a21;--line:#242833;--fg:#e6e8ee;--muted:#8b90a0;--accent:#6cf}
*{box-sizing:border-box}
body{margin:0;font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg)}
header{display:flex;align-items:center;gap:16px;padding:14px 20px;border-bottom:1px solid var(--line);flex-wrap:wrap}
header h1{font-size:15px;margin:0;font-weight:600}
#controls{display:flex;align-items:center;gap:12px;margin-left:auto;flex-wrap:wrap}
main{padding:20px;max-width:1100px;margin:0 auto}
button,select,input{font:inherit;color:var(--fg);background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:6px 10px}
button{cursor:pointer}
button:hover{border-color:var(--accent)}
#login{max-width:360px;margin:60px auto;display:flex;flex-direction:column;gap:12px}
#login input{padding:10px}
.error{color:#f86;min-height:1em}
.muted{color:var(--muted)}
.flags{display:flex;flex-direction:column;gap:8px;margin-bottom:20px}
.flag{padding:10px 14px;border-radius:8px;border:1px solid var(--line)}
.flag.ok{color:var(--muted)}
.flag.warn{background:#2a1c10;border-color:#a63;color:#fb8}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px}
.card-title{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em}
.card-big{font-size:24px;font-weight:650;margin:6px 0 8px}
.card-sub{color:var(--muted);font-size:12px}
h2{font-size:13px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin:28px 0 12px}
.charts,.hots{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px}
.metric,.hot{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px}
.metric-head{display:flex;justify-content:space-between;margin-bottom:6px}
.metric-last{font-weight:650}
svg.spark{width:100%;height:40px;display:block}
.hot-title{color:var(--muted);font-size:12px;margin-bottom:8px}
.hot table{width:100%;border-collapse:collapse}
.hot td{padding:4px 0;border-top:1px solid var(--line)}
.hot .gid{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px}
.num{text-align:right;font-variant-numeric:tabular-nums}
</style>
</head>
<body>
<header>
  <h1>Partage relay — operator</h1>
  <div id="controls" hidden>
    <label class="muted">window
      <select id="days">
        <option value="30">30d</option>
        <option value="90" selected>90d</option>
        <option value="365">365d</option>
      </select>
    </label>
    <button id="refresh" type="button">Refresh</button>
    <button id="signout" type="button">Sign out</button>
    <span id="generated" class="muted"></span>
  </div>
</header>
<main>
  <form id="login">
    <p>Enter the operator secret to view fleet metrics.</p>
    <input id="secret" type="password" autocomplete="off" placeholder="ADMIN_SECRET" />
    <button type="submit">Load dashboard</button>
    <div id="login-error" class="error"></div>
  </form>
  <div id="view" hidden></div>
</main>
<script>
var KEY = 'partage-admin-secret';
var SVGNS = 'http://www.w3.org/2000/svg';
var loginForm = document.getElementById('login');
var loginError = document.getElementById('login-error');
var secretInput = document.getElementById('secret');
var controls = document.getElementById('controls');
var generated = document.getElementById('generated');
var daysSelect = document.getElementById('days');
var view = document.getElementById('view');

function E(tag, props, kids){
  var e = document.createElement(tag);
  if (props) for (var k in props){
    if (k === 'class') e.className = props[k];
    else if (k === 'text') e.textContent = props[k];
    else if (k === 'title') e.title = props[k];
    else e.setAttribute(k, props[k]);
  }
  if (kids) for (var i = 0; i < kids.length; i++){
    var c = kids[i];
    if (c != null) e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return e;
}
function fmtInt(n){ return Number(n || 0).toLocaleString('en-US'); }
function fmtBytes(n){
  n = Number(n) || 0;
  var u = ['B','KB','MB','GB','TB'], i = 0;
  while (n >= 1000 && i < u.length - 1){ n /= 1000; i++; }
  return (i === 0 ? n : n.toFixed(2)) + ' ' + u[i];
}
function fmtDollars(cents){ return '$' + (Number(cents) / 100).toFixed(2); }
function fmtCents(cents){ return Number(cents).toFixed(2) + '¢'; }
function shortId(id){ return id.length > 12 ? id.slice(0, 12) + '…' : id; }

function sparkline(values, color){
  var W = 240, H = 40;
  var max = Math.max.apply(null, values), min = Math.min.apply(null, values);
  if (max === min){ max = min + 1; }
  var range = max - min;
  var step = values.length > 1 ? W / (values.length - 1) : 0;
  var pts = '';
  for (var i = 0; i < values.length; i++){
    var x = i * step;
    var y = H - ((values[i] - min) / range) * H;
    pts += (i ? ' ' : '') + x.toFixed(1) + ',' + y.toFixed(1);
  }
  var svg = document.createElementNS(SVGNS, 'svg');
  svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
  svg.setAttribute('class', 'spark');
  svg.setAttribute('preserveAspectRatio', 'none');
  var poly = document.createElementNS(SVGNS, 'polyline');
  poly.setAttribute('points', pts);
  poly.setAttribute('fill', 'none');
  poly.setAttribute('stroke', color);
  poly.setAttribute('stroke-width', '1.5');
  poly.setAttribute('vector-effect', 'non-scaling-stroke');
  svg.appendChild(poly);
  return svg;
}
function metric(label, values, color, fmt){
  var last = values.length ? fmt(values[values.length - 1]) : '—';
  var head = E('div', {'class':'metric-head'}, [
    E('span', {'class':'metric-label', text:label}),
    E('span', {'class':'metric-last', text:last}),
  ]);
  var chart = values.length ? sparkline(values, color) : E('div', {'class':'muted', text:'no snapshots yet'});
  return E('div', {'class':'metric'}, [head, chart]);
}
function card(title, big, subs){
  var kids = [E('div', {'class':'card-title', text:title}), E('div', {'class':'card-big', text:big})];
  for (var i = 0; i < subs.length; i++) kids.push(E('div', {'class':'card-sub', text:subs[i]}));
  return E('div', {'class':'card'}, kids);
}
function hotTable(title, rows, valueFn){
  var body = E('tbody');
  if (!rows.length){
    body.appendChild(E('tr', null, [E('td', {'class':'muted', colspan:'2', text:'none'})]));
  } else for (var i = 0; i < rows.length; i++){
    var r = rows[i];
    body.appendChild(E('tr', null, [
      E('td', {'class':'gid', title:r.groupId, text:shortId(r.groupId)}),
      E('td', {'class':'num', text:valueFn(r)}),
    ]));
  }
  return E('div', {'class':'hot'}, [E('div', {'class':'hot-title', text:title}), E('table', null, [body])]);
}
function flagBanners(flags){
  var items = [];
  if (flags.nearCapacity.active)
    items.push(flags.nearCapacity.groupsNearQuota + ' group(s) at ≥80% of a quota');
  if (flags.authProbing.active)
    items.push('Auth probing: ' + flags.authProbing.count + ' failed attempts today (threshold ' + flags.authProbing.threshold + ')');
  if (flags.rejectionSpike.active)
    items.push('Rejection spike: ' + flags.rejectionSpike.count + ' rejections today (threshold ' + flags.rejectionSpike.threshold + ')');
  if (flags.storageOverBudget.active)
    items.push('Storage over budget: ' + fmtBytes(flags.storageOverBudget.totalBytes) + ' > ' + fmtBytes(flags.storageOverBudget.budgetBytes));
  var wrap = E('div', {'class':'flags'});
  if (!items.length) return E('div', {'class':'flags'}, [E('div', {'class':'flag ok', text:'No active alerts'})]);
  for (var i = 0; i < items.length; i++) wrap.appendChild(E('div', {'class':'flag warn', text:items[i]}));
  return wrap;
}

// Pivot the flat [{day,name,value}] series into per-metric arrays. Flow counters
// are zero-filled across every observed day (a day with no event truly had 0);
// level snapshots are plotted only where a snapshot exists, so a missing sweep
// shows a gap rather than a false drop to zero.
function series(history){
  var days = [], seen = {};
  for (var i = 0; i < history.length; i++){
    var d = history[i].day;
    if (!seen[d]){ seen[d] = 1; days.push(d); }
  }
  days.sort();
  var idx = {};
  for (var j = 0; j < days.length; j++) idx[days[j]] = j;
  function zero(){ return days.map(function(){ return 0; }); }
  return {
    flow: function(name){ var a = zero(); for (var i = 0; i < history.length; i++) if (history[i].name === name) a[idx[history[i].day]] = history[i].value; return a; },
    flowSum: function(names){ var a = zero(); for (var i = 0; i < history.length; i++) if (names.indexOf(history[i].name) >= 0) a[idx[history[i].day]] += history[i].value; return a; },
    level: function(name){ var out = []; for (var i = 0; i < history.length; i++) if (history[i].name === name) out.push(history[i].value); return out; },
  };
}

function render(data){
  var now = data.now, cost = data.cost, s = series(data.history);
  generated.textContent = 'as of ' + new Date(data.generatedAt).toLocaleString();
  view.textContent = '';
  view.appendChild(flagBanners(data.flags));

  var cards = E('div', {'class':'cards'});
  cards.appendChild(card('Groups', fmtInt(now.total_groups), [now.active_groups + ' active', now.idle_groups + ' idle']));
  cards.appendChild(card('Storage', fmtBytes(now.total_bytes), [fmtInt(now.total_records) + ' records', 'logical bytes (summed)']));
  cards.appendChild(card('Active users (est.)', fmtInt(now.active_actors_7d) + ' /7d', [
    fmtInt(now.active_actors_1d) + ' /1d · ' + fmtInt(now.active_actors_30d) + ' /30d',
    fmtInt(now.distinct_actors_cumulative) + ' cumulative',
    'distinct devices, not people',
  ]));
  cards.appendChild(card('Monthly cost', fmtDollars(cost.totalCents), [
    'base ' + fmtCents(cost.baseCents) + ' · storage ' + fmtCents(cost.storageCents),
    'compute ' + fmtCents(cost.computeCents) + ' · network ' + fmtCents(cost.networkCents),
    fmtBytes(cost.monthlyBytesServed) + ' served / 30d',
  ]));
  cards.appendChild(card('Group size', fmtBytes(now.max_bytes) + ' max', [
    'p50 ' + fmtBytes(now.p50_bytes) + ' · p95 ' + fmtBytes(now.p95_bytes),
    now.groups_near_quota + ' near quota',
  ]));
  view.appendChild(cards);

  view.appendChild(E('h2', {text:'Trends'}));
  var charts = E('div', {'class':'charts'});
  charts.appendChild(metric('New groups / day', s.flow('group_created'), '#6cf', fmtInt));
  charts.appendChild(metric('Rejections / day', s.flowSum(['quota_507','rate_429','body_413']), '#f86', fmtInt));
  charts.appendChild(metric('Total storage', s.level('total_bytes'), '#6f8', fmtBytes));
  charts.appendChild(metric('Active users / 7d', s.level('active_actors_7d'), '#c9f', fmtInt));
  view.appendChild(charts);

  view.appendChild(E('h2', {text:'Hot-lists'}));
  var hots = E('div', {'class':'hots'});
  hots.appendChild(hotTable('Largest by bytes', data.hotlists.largestByBytes, function(r){ return fmtBytes(r.totalBytes); }));
  hots.appendChild(hotTable('Largest by records', data.hotlists.largestByRecords, function(r){ return fmtInt(r.recordCount); }));
  hots.appendChild(hotTable('Oldest active', data.hotlists.oldestActive, function(r){ return String(r.created).slice(0, 10); }));
  hots.appendChild(hotTable('Most actors (30d)', data.hotlists.mostActors, function(r){ return fmtInt(r.actors); }));
  view.appendChild(hots);
}

function showLogin(msg){
  view.hidden = true;
  controls.hidden = true;
  loginForm.hidden = false;
  loginError.textContent = msg || '';
}
function showView(){
  loginForm.hidden = true;
  controls.hidden = false;
  view.hidden = false;
}
async function load(){
  var secret = sessionStorage.getItem(KEY);
  if (!secret){ showLogin(''); return; }
  var res;
  try {
    res = await fetch('/api/admin/summary?days=' + encodeURIComponent(daysSelect.value), {
      headers: { Authorization: 'Bearer ' + secret },
    });
  } catch (e){ showLogin('Network error — is the relay reachable?'); return; }
  if (res.status === 401){ sessionStorage.removeItem(KEY); showLogin('Invalid secret.'); return; }
  if (!res.ok){ showLogin('Request failed (' + res.status + ').'); return; }
  render(await res.json());
  showView();
}

loginForm.addEventListener('submit', function(e){
  e.preventDefault();
  var v = secretInput.value;
  if (!v) return;
  sessionStorage.setItem(KEY, v);
  secretInput.value = '';
  load();
});
document.getElementById('refresh').addEventListener('click', load);
document.getElementById('signout').addEventListener('click', function(){ sessionStorage.removeItem(KEY); showLogin(''); });
daysSelect.addEventListener('change', load);
load();
</script>
</body>
</html>`;
