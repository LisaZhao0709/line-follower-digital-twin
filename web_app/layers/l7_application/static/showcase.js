/**
 * showcase.js — Line-Follower Digital Twin · Seven-Layer Teaching Dashboard
 * Connectivity concepts from Unit 2 are illustrated throughout the dashboard.
 * 
 * Features:
 * 1. MQTT metrics use the actual API fields (state.mqtt.sent, state.mqtt.connected, state.mqtt.prefix and related fields)
 * 2. Illustrate the four connectivity views(Physical->Transport->Exchange->Meaning)
 * 3. Inspect topics, QoS 1 and selected JSON payload fields
 * 4. Interrupt upload and feedback independently for communication experiments
 * 5. Show input, computation and output for each layer
 */

'use strict';

/* ═══════════════════════════════════════════════════════════
   LAYER CONFIG (Unit 2 connectivity concepts and application architecture)
═══════════════════════════════════════════════════════════ */
const LAYERS = [
  {
    id:1, key:'l1', color:'#4a9eff', label:'L1 Physical Layer',
    name:'Differential-drive motion and onboard PID control',
    sub:'DifferentialChassis · OnboardController · Exact ZOH',
    desc:'Simulate wheel speeds and chassis motion from normalized left/right motor commands.',
    dim:'PE Physical Entity · Physical/Link View (Unit 2 P3)',
    io:{input:'Onboard motor commands [uL, uR] in [0, 1]',
        calc:'Exact ZOH: v=(vL+vR)/2, omega=(vR-vL)/L; integrate pose (x,y,theta)',
        output:'Chassis pose and actual wheel speeds for L2 sampling'},
    files:[{name:'physical_car.py',label:'physical_car'},{name:'controller.py',label:'controller'},{name:'track.py',label:'track'}],
    defaultFile:'physical_car.py', focusFn:'update_pose',
    principle:'An exact constant-command circular arc avoids Euler truncation error. Nominal motor gain: 0.35 m/s per unit command; wheel separation: 0.12 m.',
    kpis:[
      {label:'Position x',key:d=>d.frame?.x_m?.toFixed(3)??'--',unit:'m'},
      {label:'Position y',key:d=>d.frame?.y_m?.toFixed(3)??'--',unit:'m'},
      {label:'Heading',key:d=>d.frame?(d.frame.theta_rad*180/Math.PI).toFixed(1):'--',unit:'°'},
      {label:'Left wheel speed',key:d=>d.frame?.left_speed_mps?.toFixed(3)??'--',unit:'m/s'},
    ],
    chartLabel:'Onboard PID tracking error e(t)', chartKey:'sensor_error', chartColor:'#4a9eff',
    statusFn:d=>d.source_state==='running'?{cls:'ok',text:'▶ Chassis moving'}:
      d.source_state==='paused'?{cls:'warn',text:'⏸ Chassis paused'}:
      d.source_state==='completed'?{cls:'info',text:'Experiment completed'}:{cls:'info',text:'Ready'},
  },
  {
    id:2, key:'l2', color:'#20c997', label:'L2 Acquisition Layer',
    name:'Eight-channel sensing and normalized telemetry frames',
    sub:'Gateway Normalized Record (Unit 2 P4) · SensorArray',
    desc:'Convert the simulated physical state into sampled signals with timestamps and sequence identifiers.',
    dim:'DD Digital Data · Gateway Translation (Unit 2 P4)',
    io:{input:'L1 pose and track reflectance map',
        calc:'Eight-point sensor geometry, reflectance sampling and environmental disturbances',
        output:'Timestamped telemetry frames with sensor strengths and sequence metadata'},
    files:[{name:'sensors.py',label:'sensors'},{name:'telemetry_packager.py',label:'packager'},{name:'simulation_source.py',label:'source'}],
    defaultFile:'telemetry_packager.py', focusFn:'sample_and_pack',
    principle:'The acquisition source normalizes sensor and controller signals. The transport adds session and sequence metadata before publication.',
    kpis:[
      {label:'Binary sensor array',key:d=>d.frame?.sensors?.map(v=>v?'1':'0').join(' ')??'--',unit:''},
      {label:'Observation sequence',key:d=>d.frame?.seq??'--',unit:'#'},
      {label:'Source sample time',key:d=>d.frame?.t_sim_s?.toFixed(2)??'--',unit:'s'},
      {label:'Sensor-reference RMSE',key:d=>d.metrics?.sensor_rmse?.toFixed(4)??'--',unit:''},
    ],
    chartLabel:'Sensor tracking error', chartKey:'sensor_error', chartColor:'#20c997',
    statusFn:d=>d.quality==='good'?{cls:'ok',text:'Valid sensor telemetry'}:
      d.quality==='stale'?{cls:'warn',text:'Telemetry stale'}:{cls:'info',text:'Waiting for the first sample'},
  },
  {
    id:3, key:'l3', color:'#f39c12', label:'L3 Communication Layer',
    name:'MQTT exchange, topic routing and separate channels',
    sub:'MQTT Broker · Topic Routing (Unit 2 P5–6) · QoS 1 (P7) · Channel Boundary (P13)',
    desc:'Exchange telemetry and commands through a local MQTT 3.1.1 broker with QoS 1.',
    dim:'CN Connection · Application Exchange (Unit 2 P3)',
    io:{input:'L2 observation frames from the car-source publisher',
        calc:'Serialize JSON and publish to dt/car01/{session}/telemetry with QoS 1',
        output:'Broker-delivered messages decoded by car-observer and passed to L4'},
    files:[{name:'mqtt_transport.py',label:'mqtt_transport'},{name:'broker.py',label:'broker'},{name:'broker_process.py',label:'broker_process'}],
    defaultFile:'mqtt_transport.py', focusFn:'publish_observation',
    principle:'Topics route messages; payloads carry their meaning. QoS 1 permits duplicates. Telemetry upload and command subscription can be interrupted independently.',
    kpis:[
      {label:'MQTT connection',key:d=>d.mqtt?.connected?'Connected':'Disconnected',unit:''},
      {label:'Telemetry sent',key:d=>d.mqtt?.sent??0,unit:'pkts'},
      {label:'Telemetry accepted',key:d=>d.mqtt?.received??0,unit:'pkts'},
      {label:'Broker port',key:d=>d.mqtt?.port??18884,unit:'TCP'},
    ],
    chartLabel:'Cumulative telemetry publications', chartKey:null, chartColor:'#f39c12',
    statusFn:d=>!d.mqtt?.connected?{cls:'error',text:'Broker disconnected'}:
      !d.mqtt?.upload?{cls:'warn',text:'Telemetry channel interrupted'}:{cls:'ok',text:'MQTT 3.1.1 connected'},
  },
  {
    id:4, key:'l4', color:'#9b59b6', label:'L4 Data Management',
    name:'Schema validation, deduplication, gap checks and storage',
    sub:'Idempotence (Unit 2 P8) · TelemetryReceiver · ExperimentStore',
    desc:'Validate telemetry, reject duplicate or invalid samples, record sequence gaps and export data.',
    dim:'DD Digital Data · Idempotent Write (Unit 2 P8)',
    io:{input:'Decoded JSON messages from L3',
        calc:'Check schema, session, sequence ordering and sample gaps',
        output:'Validated observation history for L5 and CSV export'},
    files:[{name:'validator.py',label:'validator'},{name:'storage.py',label:'storage'}],
    defaultFile:'validator.py', focusFn:'accept',
    principle:'QoS 1 can redeliver messages. Session and sequence checks prevent duplicate measurements from advancing the model; sample-index gaps mark missing observations.',
    kpis:[
      {label:'Valid-data indicator',key:d=>d.mqtt?.received?(((d.mqtt.received-(d.mqtt.rejected??0))/d.mqtt.received)*100).toFixed(1):'100',unit:'%'},
      {label:'Rejected messages',key:d=>d.mqtt?.rejected??0,unit:'msgs'},
      {label:'Sequence gaps',key:d=>d.mqtt?.gaps??0,unit:'msgs'},
      {label:'Duplicates blocked',key:d=>d.mqtt?.duplicates??0,unit:'msgs'},
    ],
    chartLabel:'Observation-gap marker (gap_before)', chartKey:'gap_before', chartColor:'#9b59b6',
    statusFn:d=>d.quality==='good'?{cls:'ok',text:'Valid recent telemetry; inspect gap counts separately'}:
      d.quality==='stale'?{cls:'warn',text:'Data freshness expired'}:{cls:'info',text:'Waiting for validated telemetry'},
  },
  {
    id:5, key:'l5', color:'#e74c3c', label:'L5 Twin Model',
    name:'Healthy reference, measured comparison and prediction',
    sub:'TwinModel · Fixed Healthy Reference · Residual Analysis',
    desc:'Predict nominal behavior without reading fault settings, then compare it with received observations.',
    dim:'VE Virtual Entity · Information Meaning (Unit 2 P3)',
    io:{input:'Validated L4 commands, wheel speeds, pose and timing',
        calc:'Nominal speed = 0.35 × command; signed speed residuals and pose innovation',
        output:'Wheel residuals, position and heading innovation, healthy replay and conditional forecast'},
    files:[{name:'twin_model.py',label:'twin_model'}], defaultFile:'twin_model.py', focusFn:'update',
    principle:'The twin never reads source fault settings. A fixed gain of 0.35 provides a healthy reference. One-step prediction is corrected by observations; continuous healthy replay is not corrected between gaps.',
    kpis:[
      {label:'Left residual ΔvL',key:d=>signed(d.twin?.residual_left_mps),unit:'m/s'},
      {label:'Right residual ΔvR',key:d=>signed(d.twin?.residual_right_mps),unit:'m/s'},
      {label:'Position innovation',key:d=>d.twin?.prediction_valid?(d.twin.innovation_m*1000).toFixed(3):'--',unit:'mm'},
      {label:'Model updates',key:d=>d.twin?.updates??'--',unit:''},
    ],
    chartLabel:'Signed residuals · red: left / blue: right · source time', chartKey:'residual_mps', chartColor:'#e74c3c',
    statusFn:d=>{
      if(!d.twin)return {cls:'info',text:'Waiting for valid telemetry'};
      if(d.quality!=='good')return {cls:'warn',text:'Data stale; retaining the last observation'};
      if(d.source_state==='completed')return {cls:'info',text:'Experiment completed; showing the final sample'};
      if(!d.twin.prediction_valid)return {cls:'info',text:'Reference aligned; waiting for a consecutive sample'};
      const issue=d.metrics?.findings?.find(f=>f.code?.startsWith('drive_'));
      if(issue)return {cls:'warn',text:issue.title+' · consecutive-window evidence'};
      if(d.source_state==='paused')return {cls:'info',text:'Paused; heartbeats do not advance the model'};
      if(d.twin.residual_mps>.005)return {cls:'warn',text:'Wheel-speed deviation; collecting diagnostic evidence'};
      return {cls:'ok',text:'Model updating; zero residual means agreement with the reference'};
    },
  },
  {
    id:6, key:'l6', color:'#2ecc71', label:'L6 Services and Feedback',
    name:'Window-based diagnostics and candidate control settings',
    sub:'analyze() · CommandService · Closed-loop Feedback',
    desc:'Assess the last second of received observations and generate evidence, candidate settings and commands.',
    dim:'Ss Services · Closed-loop Feedback',
    io:{input:'L4 observation history and L5 healthy references and residuals',
        calc:'Drive-response ratios, error zero crossings, tracking error and saturation',
        output:'Diagnostic findings, candidate PID settings and acknowledged source commands'},
    files:[{name:'diagnostics.py',label:'diagnostics'},{name:'command_service.py',label:'cmd_service'}],
    defaultFile:'diagnostics.py', focusFn:'analyze',
    principle:'Candidate PID settings require a repeatable experiment from the same initial state. A command is confirmed only after the source acknowledgement arrives.',
    kpis:[
      {label:'Window tracking MAE',key:d=>d.metrics?.mae?.toFixed(4)??'--',unit:''},
      {label:'Error zero crossings',key:d=>d.metrics?.zero_crossings?.toFixed(1)??'--',unit:'/s'},
      {label:'Command saturation',key:d=>d.metrics?.saturation!=null?(d.metrics.saturation*100).toFixed(1):'--',unit:'%'},
      {label:'Diagnostic status',key:d=>d.metrics?.status??'--',unit:''},
    ],
    chartLabel:'Tracking error', chartKey:'sensor_error', chartColor:'#2ecc71',
    statusFn:d=>{
      const s=d.metrics?.status;
      if(!s||s.startsWith('Waiting'))return {cls:'info',text:s??'Waiting for a diagnostic window'};
      return /stable|completed|ready/i.test(s)?{cls:'ok',text:s}:{cls:'warn',text:s};
    },
  },
  {
    id:7, key:'l7', color:'#95a5a6', label:'L7 Application Layer',
    name:'State dashboard, API routes and user interaction',
    sub:'create_app() · REST API · Experiment Dashboard',
    desc:'Present the model, data and services from all layers with controls and downloadable evidence.',
    dim:'Ss Services · Application Presentation (Unit 2 P3)',
    io:{input:'The complete Runtime.snapshot() state',calc:'REST JSON, Canvas trajectory rendering and chart updates',
        output:'Interactive dashboard, experiment controls and CSV/JSON downloads'},
    files:[{name:'web_api.py',label:'web_api'}], defaultFile:'web_api.py', focusFn:'state',
    principle:'The user interface supports observation, controlled simulation experiments and acknowledged commands to the source.',
    kpis:[
      {label:'Source simulation time',key:d=>d.source_time_s?.toFixed(2)??'--',unit:'s'},
      {label:'Accepted telemetry',key:d=>d.mqtt?.received??'--',unit:'frames'},
      {label:'Data quality',key:d=>d.quality??'--',unit:''},
      {label:'Saved experiments',key:d=>d.records?.length??0,unit:'runs'},
    ],
    chartLabel:'Integrated tracking-error stream', chartKey:'sensor_error', chartColor:'#95a5a6',
    statusFn:d=>({cls:'ok',text:'Integrated application running'}),
  },
];

const LAYER_BY_ID = Object.fromEntries(LAYERS.map(l => [l.id, l]));

/* ═══════════════════════════════════════════════════════════
   GLOBAL STATE
═══════════════════════════════════════════════════════════ */
const State = {
  currentPage: 'home',
  currentLayerId: 1,
  apiData: null,
  codeCache: {},
  chartBuffers: {},
  codeMode: 'follow',
  activeTab: {},
  faultMismatch: false,
  pendingCommand: null,
};

/* ═══════════════════════════════════════════════════════════
   POLLER (Single shared state poller)
═══════════════════════════════════════════════════════════ */
const Poller = {
  _tid: null,
  _cb: null,
  _busy: false,
  start() {
    this._tick();
    this._tid = setInterval(() => this._tick(), 200);
  },
  bind(fn) { this._cb = fn; },
  async _tick() {
    if (this._busy) return;
    this._busy = true;
    try {
      const r = await fetch('/api/state');
      if (!r.ok) return;
      const data = await r.json();
      if (!State.apiData) State.faultMismatch = data.frame?.config?.motor_left_factor === .8;
      State.apiData = data;
      this._cb?.(data);
      CtrlBar.update(data);
    } catch (error) { console.error('State update failed', error); }
    finally { this._busy = false; }
  },
};

/* ═══════════════════════════════════════════════════════════
   CONTROL BAR (Global controls)
═══════════════════════════════════════════════════════════ */
const CtrlBar = {
  init() {
    document.getElementById('btn-run').onclick   = () => this.send('run');
    document.getElementById('btn-pause').onclick = () => this.send('pause');
    document.getElementById('btn-step').onclick  = () => this.send('step');
    document.getElementById('btn-reset').onclick = () => this.send('reset');
    document.getElementById('speed-sel').onchange = e => this.send('run', { speed: +e.target.value });
  },
  async send(action, extra = {}) {
    const data = State.apiData;
    let cfg = {};
    if (data?.frame?.config) {
      Object.assign(cfg, data.frame.config);
    } else {
      cfg = { Kp: 0.45, Ki: 0.015, Kd: 0.03, speed: 4.0, environment_level: 1, environment_seed: 7, motor_left_factor: 1.0, dropout: false };
    }
    Object.assign(cfg, extra);
    if (!Object.hasOwn(extra, 'motor_left_factor')) cfg.motor_left_factor = State.faultMismatch ? .8 : 1;
    try {
      const response = await fetch('/api/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, config: cfg }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? 'Command not accepted');
      State.pendingCommand = {id: result.command_id, message:'Submitted; awaiting source acknowledgement'};
      return result;
    } catch (error) {
      State.pendingCommand = {id:null, message:'Operation failed: ' + error.message};
      return null;
    }
  },
  update(data) {
    const s = data.source_state;
    const dot = document.getElementById('state-dot');
    const label = document.getElementById('state-label');
    const t = document.getElementById('sim-time-top');
    if (dot) dot.className = s === 'running' ? 'running' : s === 'paused' ? 'paused' : 'idle';
    if (label) label.textContent = ({running:'Running', paused:'Paused', completed:'Completed', idle:'Idle'})[s] ?? s;
    if (t) t.textContent = `t = ${(data.source_time_s ?? 0).toFixed(2)}s`;
  },
};

/* ═══════════════════════════════════════════════════════════
   ROUTER (SPA hash routing)
═══════════════════════════════════════════════════════════ */
const Router = {
  init() {
    window.addEventListener('hashchange', () => this.dispatch());
    this.dispatch();
  },
  dispatch() {
    const hash = location.hash || '#home';
    const m = hash.match(/^#layer\/(\d)$/);
    if (m) {
      const id = +m[1];
      if (LAYER_BY_ID[id]) { showLayerPage(id); return; }
    }
    showHomePage();
  },
  go(hash) { location.hash = hash; },
};

function goHome() { Router.go('#home'); }
function goLayer(n) { Router.go(`#layer/${n}`); }

/* ═══════════════════════════════════════════════════════════
   HOME PAGE (Home: seven-layer overview and schematic flow animation)
═══════════════════════════════════════════════════════════ */
function showHomePage() {
  State.currentPage = 'home';
  document.getElementById('bottom-nav').classList.add('hidden');
  document.querySelectorAll('.lnav-btn').forEach(b => b.classList.toggle('active', b.dataset.l === 'h'));

  const page = document.getElementById('home-page');
  document.getElementById('layer-page').classList.remove('active');
  page.classList.add('active');

  Poller.bind(renderHome);
  if (State.apiData) renderHome(State.apiData);
}

function renderHome(data) {
  LAYERS.forEach(layer => {
    const card = document.getElementById(`card-live-${layer.id}`);
    if (!card) return;
    const kpi = layer.kpis[0];
    card.textContent = kpi.label + ': ' + kpi.key(data) + ' ' + kpi.unit;
  });
  const hTime  = document.getElementById('hb-time');
  const hQual  = document.getElementById('hb-qual');
  const hMqtt  = document.getElementById('hb-mqtt');
  if (hTime) hTime.textContent = (data.source_time_s ?? 0).toFixed(2) + 's';
  if (hQual) hQual.textContent = data.quality ?? '--';
  if (hMqtt) hMqtt.textContent = data.mqtt?.connected ? `✅ Online (${data.mqtt.sent} frames)` : '❌ Offline';
}

function buildHomePage() {
  const page = document.getElementById('home-page');
  page.innerHTML = `
    <div class="hero">
      <h1>Line-Follower Digital Twin · Seven-Layer Architecture</h1>
      <p>Seven connected layers · Live MQTT 3.1.1 · Simulation-based experiments</p>
      <div class="badges">
        <span class="badge-pill" style="color:#4a9eff;border-color:#4a9eff;background:rgba(74,158,255,.1)">🔵 PE Physical Entity</span>
        <span class="badge-pill" style="color:#e74c3c;border-color:#e74c3c;background:rgba(231,76,60,.1)">🔴 VE Virtual Entity</span>
        <span class="badge-pill" style="color:#9b59b6;border-color:#9b59b6;background:rgba(155,89,182,.1)">🟣 DD Digital Data</span>
        <span class="badge-pill" style="color:#f39c12;border-color:#f39c12;background:rgba(243,156,18,.1)">🟡 CN Connection</span>
        <span class="badge-pill" style="color:#2ecc71;border-color:#2ecc71;background:rgba(46,204,113,.1)">🟢 Ss Services</span>
      </div>
    </div>

    <div class="heartbeat">
      <div class="hb-item">🕒 Simulation time <span class="hb-val" id="hb-time">--</span></div>
      <div class="hb-item">📊 Data quality <span class="hb-val" id="hb-qual">--</span></div>
      <div class="hb-item">📡 MQTT connection <span class="hb-val" id="hb-mqtt">--</span></div>
      <div class="hb-item">🔄 Source time step <span class="hb-val">20ms (50Hz)</span></div>
    </div>

    <div class="layer-grid">
      ${LAYERS.map(l => `
        <div class="layer-card" data-l="${l.id}" onclick="goLayer(${l.id})">
          <div class="card-num">${l.label}</div>
          <div class="card-name">${l.name}</div>
          <div class="card-desc">${l.desc}</div>
          <div class="card-io"><strong>Input:</strong> ${l.io.input.slice(0,25)}…</div>
          <div class="card-live" id="card-live-${l.id}">Loading…</div>
          <div class="card-enter">Explore this layer →</div>
        </div>`).join('')}
    </div>

    <div class="flow-wrap">
      <canvas id="flow-canvas"></canvas>
    </div>
  `;
  startFlowAnimation();
}

/* ─── Data Flow Canvas ─── */
let flowAnim = null;
const particles = [];
function startFlowAnimation() {
  const canvas = document.getElementById('flow-canvas');
  if (!canvas) return;
  cancelAnimationFrame(flowAnim);
  const ctx = canvas.getContext('2d');
  const nodes = LAYERS.map((l, i) => ({ x: 0, y: 0, color: l.color, label: l.label }));

  function resize() {
    canvas.width  = canvas.offsetWidth;
    canvas.height = canvas.offsetHeight;
    const W = canvas.width, H = canvas.height;
    const pad = 60;
    nodes.forEach((n, i) => {
      n.x = pad + (W - 2*pad) * i / (nodes.length - 1);
      n.y = H / 2;
    });
  }
  resize();
  window.addEventListener('resize', resize);

  for (let i = 0; i < 14; i++) {
    particles.push({ seg: Math.floor(Math.random() * 6), t: Math.random(), speed: 0.005 + Math.random()*0.004 });
  }

  function draw() {
    const W = canvas.width, H = canvas.height;
    ctx.clearRect(0, 0, W, H);

    for (let i = 0; i < nodes.length - 1; i++) {
      const a = nodes[i], b = nodes[i+1];
      const grad = ctx.createLinearGradient(a.x, a.y, b.x, b.y);
      grad.addColorStop(0, a.color + '55');
      grad.addColorStop(1, b.color + '55');
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
      ctx.strokeStyle = grad; ctx.lineWidth = 2; ctx.stroke();
    }
    nodes.forEach(n => {
      ctx.beginPath(); ctx.arc(n.x, n.y, 7, 0, Math.PI*2);
      ctx.fillStyle = n.color; ctx.fill();
      ctx.fillStyle = '#fff'; ctx.font = '10px monospace';
      ctx.textAlign = 'center';
      ctx.fillText('L'+(nodes.indexOf(n)+1), n.x, n.y + 20);
    });
    const running = State.apiData?.source_state === 'running';
    particles.forEach(p => {
      p.t += p.speed * (running ? 1 : 0.3);
      if (p.t >= 1) { p.t = 0; p.seg = (p.seg + 1) % 6; }
      const a = nodes[p.seg], b = nodes[p.seg+1];
      const px = a.x + (b.x - a.x) * p.t;
      const py = a.y + (b.y - a.y) * p.t;
      ctx.beginPath(); ctx.arc(px, py, 3.5, 0, Math.PI*2);
      ctx.fillStyle = nodes[p.seg].color; ctx.fill();
    });
    flowAnim = requestAnimationFrame(draw);
  }
  draw();
}

/* ═══════════════════════════════════════════════════════════
   LAYER DETAIL PAGE
═══════════════════════════════════════════════════════════ */
async function showLayerPage(id) {
  State.currentPage = 'layer';
  State.currentLayerId = id;
  const layer = LAYER_BY_ID[id];
  cancelAnimationFrame(flowAnim);

  document.getElementById('home-page').classList.remove('active');
  const lp = document.getElementById('layer-page');
  lp.classList.add('active');

  document.querySelectorAll('.lnav-btn').forEach(b => {
    b.classList.toggle('active', +b.dataset.l === id);
  });

  const bn = document.getElementById('bottom-nav');
  bn.classList.remove('hidden');
  const prevId = id - 1;
  const nextId = id + 1;
  document.getElementById('btn-prev').onclick = () => prevId < 1 ? goHome() : goLayer(prevId);
  document.getElementById('btn-prev').innerHTML = prevId < 1
    ? '<span class="arrow">←</span> Back to overview'
    : `<span class="arrow">←</span> L${prevId} · ${LAYER_BY_ID[prevId]?.name?.slice(0,6)}…`;
  const btnNext = document.getElementById('btn-next');
  if (nextId > 7) {
    btnNext.innerHTML = '<span class="arrow">↩</span> Back to overview';
    btnNext.onclick = () => goHome();
    btnNext.style.borderColor = '';
    btnNext.style.color = '';
  } else {
    btnNext.innerHTML = `L${nextId} · ${LAYER_BY_ID[nextId]?.name?.slice(0,6)}… <span class="arrow">→</span>`;
    btnNext.onclick = () => goLayer(nextId);
    btnNext.style.borderColor = LAYER_BY_ID[nextId].color;
    btnNext.style.color = LAYER_BY_ID[nextId].color;
  }
  document.getElementById('nav-center-text').textContent = `${layer.label} — ${layer.dim}`;

  buildLayerShell(layer);

  const filename = State.activeTab[id] || layer.defaultFile;
  Poller.bind(data => renderLayerDash(data, layer));
  if (State.apiData) renderLayerDash(State.apiData, layer);
  await loadCode(layer, filename);
}

function buildLayerShell(layer) {
  const lp = document.getElementById('layer-page');
  lp.style.setProperty('--lc', layer.color);

  const isL3 = layer.id === 3;
  const isL6 = layer.id === 6;

  lp.innerHTML = `
    <div class="layer-header" style="border-top-color:${layer.color}">
      <span class="lh-badge" style="color:${layer.color};border-color:${layer.color}">${layer.label}</span>
      <div>
        <div class="lh-title">${layer.name}</div>
        <div class="lh-sub" style="color:${layer.color};opacity:0.85">${layer.sub}</div>
      </div>
    </div>

    <div class="layer-body">
      <!-- LEFT: Code Studio -->
      <div class="code-studio">
        <div class="cs-tabs">
          ${layer.files.map(f => `
            <button class="cs-tab ${f.name === (State.activeTab[layer.id]||layer.defaultFile) ? 'active' : ''}"
              data-file="${f.name}" onclick="switchTab(${layer.id},'${f.name}',this)">${f.label}</button>
          `).join('')}
        </div>
        <div class="cs-toolbar">
          <span>Source code and principles</span>
          <div class="mode-toggle">
            <button class="${State.codeMode==='follow'?'on':''}" onclick="setCodeMode('follow',this)">▶ Follow execution</button>
            <button class="${State.codeMode==='static'?'on':''}" onclick="setCodeMode('static',this)">📌 Static explanation</button>
          </div>
        </div>

        <div class="code-scroll" id="code-scroll">
          <div class="loading-state" style="padding:20px;color:var(--text-muted)">Loading source code…</div>
        </div>

        <!-- IO Banner -->
        <div class="io-banner">
          <div class="io-item"><span class="io-tag">📥 Input:</span> ${layer.io.input}</div>
          <div class="io-item"><span class="io-tag">📤 Output:</span> ${layer.io.output}</div>
        </div>

        <div class="principle-card">
          <strong>🔬 Operating principles:</strong>${layer.principle}
        </div>
      </div>

      <!-- RIGHT: Dashboard -->
      <div class="dashboard" id="layer-dash">
        <div class="kpi-row">
          ${layer.kpis.map((k,i) => `
            <div class="kpi-card">
              <div class="kpi-label">${k.label}</div>
              <div class="kpi-val" id="kpi-${layer.id}-${i}">--<span class="kpi-unit">${k.unit}</span></div>
            </div>`).join('')}
        </div>

        ${layer.id === 2 ? `
          <div class="kpi-card" style="padding:8px 10px">
            <div class="kpi-label">Eight-channel binary sensor array S[8]</div>
            <div class="sensor-strip" id="sensor-leds">
              ${Array(8).fill(0).map((_,i)=>`<div class="sensor-led" id="led-${i}"></div>`).join('')}
            </div>
          </div>` : ''}

        ${isL3 ? buildL3MqttWorkbench() : ''}
        ${layer.id === 5 ? buildL5Workbench() : ''}

        <div class="chart-wrap">
          <div class="chart-title">${layer.chartLabel}</div>
          <canvas class="chart-canvas" id="layer-chart-${layer.id}"></canvas>
        </div>

        <div class="status-box">
          <div class="stitle">Runtime status</div>
          <div id="status-tag-wrap"><span class="status-tag info">Waiting for data…</span></div>
          <div id="status-msg" style="font-size:11px;color:var(--text-muted);margin-top:4px"></div>
        </div>

        ${isL6 ? buildL6Panel() : ''}

        <div class="chart-wrap">
          <div class="chart-title">📋 Runtime event log</div>
          <div class="event-log" id="event-log">Waiting for events…</div>
        </div>
      </div>
    </div>
  `;

  if (isL3) bindL3Events();
  if (isL6) {
    const checkbox = document.getElementById('fi-mismatch');
    if (checkbox) checkbox.checked = State.faultMismatch;
  }
}

/* ─── L3 Specific: MQTT Workbench & Packet Inspector ─── */
function signed(value, digits = 4) {
  return Number.isFinite(value) ? (value >= 0 ? '+' : '') + value.toFixed(digits) : '--';
}

function buildL5Workbench() {
  return `<section class="twin-workbench" aria-label="Layer 5 twin comparison experiments">
    <div class="twin-heading"><strong>What is the twin doing?</strong><a href="/api/analysis">Export twin report</a></div>
    <div class="twin-actions">
      <button class="ctrl-btn primary" id="l5-healthy" onclick="runTwinExperiment(false)">① Healthy baseline</button>
      <button class="ctrl-btn danger" id="l5-fault" onclick="runTwinExperiment(true)">② Left wheel −20%</button>
      <button class="ctrl-btn" onclick="goLayer(6)">③ View L6 evidence →</button>
    </div>
    <div id="l5-command" class="twin-command" role="status">Start an experiment, then wait for its MQTT source acknowledgement.</div>
    <div class="twin-sync" id="l5-sync">Waiting for the first valid observation…</div>
    <table class="twin-table"><caption>Current sample: nominal and measured wheel speeds (m/s)</caption>
      <thead><tr><th>Wheel</th><th>Nominal</th><th>Measured</th><th>Measured − nominal</th></tr></thead>
      <tbody id="l5-speeds"><tr><td colspan="4">Waiting for telemetry</td></tr></tbody>
    </table>
    <div class="twin-heading"><strong>Measured trajectory and healthy replay</strong><span id="l5-drift">--</span></div>
    <canvas id="l5-pose" aria-label="Measured and healthy-reference trajectories, with a one-second constant-command forecast" role="img"></canvas>
    <p class="twin-legend"><span>● Blue: observations</span><span>● Orange: healthy replay</span><span>┄ Purple: hold commands for 1 s</span></p>
    <div class="twin-steps" id="l5-steps"></div>
    <details class="twin-note"><summary>How to read the chart and compare experiments</summary>
      <p>Zero residual is a healthy result. Updates and trajectories show that the model is active. Both experiments restart with the same default PID, ideal sensors and seed; only the simulated left-wheel response changes.</p>
      <p>The orange reference is aligned at initialization and after gaps, without correction between observations. Purple assumes constant commands; the actual PID will update them. Both axes use the same scale.</p>
    </details>
    <div class="twin-actions"><button class="ctrl-btn" id="l5-upload" onclick="toggleChannel('upload')">Pause telemetry upload</button><a href="/api/export">Export received CSV</a></div>
    <p class="twin-note">The source can keep running while upload is interrupted. The twin retains its last observation and realigns after recovery; gaps are neither connected nor evaluated as valid innovation.</p>
  </section>`;
}

async function runTwinExperiment(fault) {
  const result = await CtrlBar.send('run', {
    Kp:.45, Ki:.015, Kd:.03, environment_level:0, environment_seed:7,
    speed:+document.getElementById('speed-sel').value, dropout:false,
    motor_left_factor:fault ? .8 : 1,
  });
  if (result) State.faultMismatch = fault;
  const message = document.getElementById('l5-command');
  if (message) message.textContent = State.pendingCommand.message;
}

function renderL5Workbench(data) {
  const twin = data.twin, frame = data.frame;
  const command = data.command;
  const commandEl = document.getElementById('l5-command');
  if (commandEl && State.pendingCommand) {
    commandEl.textContent = command?.command_id === State.pendingCommand.id
      ? ({pending:'Submitted; awaiting source acknowledgement', applied:'Applied at source · ' + (command.run_id ?? ''),
          timeout:'Acknowledgement timed out; check the source to determine the outcome', rejected:'Source rejected: ' + command.message,
          failed:'Command publication failed'})[command.status] ?? command.message
      : State.pendingCommand.message;
  }
  const upload = document.getElementById('l5-upload');
  if (upload) upload.textContent = data.mqtt?.upload ? 'Pause telemetry upload' : 'Resume telemetry upload';
  document.querySelectorAll('#l5-healthy, #l5-fault').forEach(button => {
    button.disabled = command?.status === 'pending' || !data.mqtt?.connected || !data.mqtt?.upload;
  });
  if (!twin || !frame) return;
  document.getElementById('l5-sync').textContent =
    `Source ${data.source_time_s.toFixed(2)} s → Model ${twin.t_sim_s.toFixed(2)} s · Sample #${twin.sample_index} · ` +
    (data.quality !== 'good' ? 'Data stale; showing the last observation' :
      data.source_state === 'running' ? 'Receiving consecutive observations' : 'No new sample; heartbeats do not advance the model');
  document.getElementById('l5-speeds').innerHTML = ['left','right'].map((side,i) =>
    `<tr><th>${i ? 'Right' : 'Left'}</th><td>${twin['expected_'+side+'_mps'].toFixed(4)}</td>` +
    `<td>${frame[side+'_speed_mps'].toFixed(4)}</td><td class="${Math.abs(twin['residual_'+side+'_mps'])>.005?'deviated':''}">${signed(twin['residual_'+side+'_mps'])}</td></tr>`).join('');
  document.getElementById('l5-drift').textContent = `Reference drift ${(twin.nominal_drift_m*1000).toFixed(1)} mm`;
  document.getElementById('l5-steps').textContent = twin.prediction_valid
    ? `Previous commands → ${Math.round(twin.prediction_dt_s*1000)} ms arc prediction → position correction ${(twin.innovation_m*1000).toFixed(3)} mm; heading correction ${signed(twin.innovation_theta_rad*180/Math.PI,3)}°. Healthy replay duration: ${twin.nominal_elapsed_s.toFixed(2)} s.`
    : twin.phase === 'resynced' ? 'Observation gap: reference realigned. Missing commands are unknown; innovation for this interval is invalid.'
    : 'The first sample initializes the pose reference. One-step prediction and innovation start with the next consecutive sample.';
  drawTwinPose(data);
}

function drawTwinPose(data) {
  const canvas = document.getElementById('l5-pose');
  if (!canvas || !data.twin) return;
  const ctx = canvas.getContext('2d'), W = canvas.width = canvas.clientWidth, H = canvas.height = canvas.clientHeight;
  const history = data.history.slice(-100), twin = data.twin;
  const forecast = data.quality === 'good' ? twin.forecast : [];
  const points = history.flatMap(f=>[[f.x_m,f.y_m],[f.nominal_x_m,f.nominal_y_m]])
    .concat(forecast.map(f=>[f.x_m,f.y_m]));
  if (!points.length || !W) return;
  const xs=points.map(p=>p[0]), ys=points.map(p=>p[1]);
  const cx=(Math.min(...xs)+Math.max(...xs))/2, cy=(Math.min(...ys)+Math.max(...ys))/2;
  const scale=Math.min((W-65)/Math.max(.16,Math.max(...xs)-Math.min(...xs)),
    (H-45)/Math.max(.16,Math.max(...ys)-Math.min(...ys)));
  const xy=(x,y)=>[W/2+(x-cx)*scale,H/2-(y-cy)*scale];
  ctx.clearRect(0,0,W,H); ctx.fillStyle='#0d1117';ctx.fillRect(0,0,W,H);
  ctx.strokeStyle='#ffffff0c';ctx.lineWidth=1;
  for(let i=1;i<6;i++){ctx.beginPath();ctx.moveTo(i*W/6,0);ctx.lineTo(i*W/6,H);ctx.stroke();}
  function trace(series,xkey,ykey,color,dashed=false){
    ctx.beginPath();ctx.setLineDash(dashed?[5,4]:[]);let connected=false;
    series.forEach(f=>{const p=xy(f[xkey],f[ykey]);
      if(!connected||f.gap_before)ctx.moveTo(...p);else ctx.lineTo(...p);connected=true;});
    ctx.strokeStyle=color;ctx.lineWidth=2;ctx.stroke();ctx.setLineDash([]);
  }
  trace(history,'nominal_x_m','nominal_y_m','#f39c12');
  trace(history,'x_m','y_m','#4a9eff');
  trace(forecast,'x_m','y_m','#bc8cff',true);
  [[twin.nominal_x_m,twin.nominal_y_m,twin.nominal_theta_rad,'#f39c12'],
   [twin.x_m,twin.y_m,twin.theta_rad,'#4a9eff']].forEach(([x,y,theta,color])=>{
    const p=xy(x,y);ctx.beginPath();ctx.arc(...p,5,0,Math.PI*2);ctx.fillStyle=color;ctx.fill();
    ctx.beginPath();ctx.moveTo(...p);ctx.lineTo(p[0]+17*Math.cos(theta),p[1]-17*Math.sin(theta));ctx.strokeStyle=color;ctx.stroke();
  });
  ctx.fillStyle='#8b949e';ctx.font='11px monospace';
  ctx.fillText(`x → / y ↑   100 mm = ${(scale*.1).toFixed(0)} px`,12,H-10);
  if(data.quality !== 'good')ctx.fillText('Stale observations · trajectory frozen',12,18);
}

function drawTwinResiduals(data, canvas) {
  const ctx=canvas.getContext('2d'), W=canvas.width=canvas.clientWidth, H=canvas.height=canvas.clientHeight;
  const history=data.history.filter(f=>Number.isFinite(f.residual_left_mps));
  ctx.clearRect(0,0,W,H);
  if(!history.length || !W) return;
  const max=Math.max(.03,...history.flatMap(f=>[Math.abs(f.residual_left_mps),Math.abs(f.residual_right_mps)]))*1.15;
  const first=history[0].t_sim_s,last=history[history.length-1].t_sim_s,span=Math.max(.02,last-first);
  const x=f=>48+(f.t_sim_s-first)/span*(W-60), y=v=>12+(1-v/max)*(H-36)/2;
  ctx.strokeStyle='#ffffff30';ctx.beginPath();ctx.moveTo(48,y(0));ctx.lineTo(W-12,y(0));ctx.stroke();
  ['left','right'].forEach((side,i)=>{
    ctx.strokeStyle=i?'#4a9eff':'#f85149';ctx.lineWidth=2;ctx.beginPath();
    history.forEach((f,j)=>{if(j===0||f.gap_before)ctx.moveTo(x(f),y(f['residual_'+side+'_mps']));
      else ctx.lineTo(x(f),y(f['residual_'+side+'_mps']));});ctx.stroke();
  });
  ctx.fillStyle='#8b949e';ctx.font='10px monospace';ctx.textAlign='left';
  ctx.fillText(max.toFixed(3),1,15);ctx.fillText('0',30,y(0)+3);ctx.fillText((-max).toFixed(3),1,H-24);
  ctx.fillText(first.toFixed(1)+' s',48,H-4);ctx.textAlign='right';ctx.fillText(last.toFixed(1)+' s',W-12,H-4);
}

function buildL3MqttWorkbench() {
  return `
    <div class="mqtt-workbench">
      <div class="mwb-header">
        <span class="mwb-title">📡 MQTT workbench (Unit 2 P5–7, P13)</span>
        <span class="mwb-badge">QoS 1 · At Least Once</span>
      </div>

      <div class="mwb-grid">
        <div class="mwb-cell">
          <div class="mwb-label">Telemetry topic</div>
          <div class="mwb-value" id="mqtt-topic-telemetry">dt/car01/.../telemetry</div>
        </div>
        <div class="mwb-cell">
          <div class="mwb-label">Command topic</div>
          <div class="mwb-value" id="mqtt-topic-command">dt/car01/.../command</div>
        </div>
      </div>

      <div>
        <div class="mwb-label" style="margin-bottom:4px">📦 Live payload field inspector</div>
        <div class="packet-viewer" id="packet-json">// Waiting for a network message...</div>
      </div>

      <!-- Unit 2 Page 13: Protect Boundary between Monitoring and Control -->
      <div>
        <div class="mwb-label" style="margin-bottom:4px">🔌 Channel interruption experiment</div>
        <div class="channel-switches">
          <button class="c-switch-btn on" id="btn-toggle-upload" onclick="toggleChannel('upload')">
            <span>● Telemetry channel</span> <strong id="status-upload">Enabled</strong>
          </button>
          <button class="c-switch-btn on" id="btn-toggle-feedback" onclick="toggleChannel('feedback')">
            <span>● Command channel</span> <strong id="status-feedback">Enabled</strong>
          </button>
        </div>
      </div>
    </div>
  `;
}

function bindL3Events() {}

async function toggleChannel(channel) {
  const data = State.apiData?.mqtt;
  if (!data) return;
  const current = channel === 'upload' ? data.upload : data.feedback;
  const next = !current;
  try {
    const res = await fetch('/api/transport', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ channel, enabled: next }),
    });
    if (res.ok) {
      if (channel === 'upload') data.upload = next;
      else data.feedback = next;
    }
  } catch (_) {}
}

/* ─── L6 Feedback Panel: Interactive service and feedback workbench ─── */
function buildL6Panel() {
  return `
    <div class="feedback-panel">
      <div class="fp-title">
        <span class="dot"></span>🩺 Health evidence and feedback actions
        <a href="/api/analysis" target="_blank" style="margin-left:auto;font-size:10px;color:var(--l6);text-decoration:none;">
          Export analysis JSON ↗
        </a>
      </div>

      <!-- 1. Diagnostic findings -->
      <div class="findings-list" id="findings-list">
        <div style="font-size:11px;color:var(--text-muted)">Collecting a diagnostic observation window…</div>
      </div>

      <!-- 2. Simulation recovery and comparison controls -->
      <div id="remedy-box" style="display:none;background:rgba(0,0,0,0.3);border:1px solid var(--orange);border-radius:6px;padding:8px 10px;margin-bottom:8px;">
        <div style="font-size:11px;font-weight:700;color:var(--orange);margin-bottom:3px;">
          🛠️ Drive-response mismatch observed
        </div>
        <div style="font-size:10px;color:var(--text-muted);margin-bottom:6px;">
          The observation window indicates a command-to-speed mismatch. Inspect the drive chain. These controls only clear the simulation fault and start a new comparison run.
        </div>
        <div class="fault-action-row">
          <button class="btn-remedy fix" onclick="remedyMotorFault()">
            Clear simulated fault and rerun
          </button>
          <button class="btn-remedy reset" onclick="retestBenchmark()">
            🔄 Run default baseline
          </button>
        </div>
      </div>

      <!-- 3. Candidate-parameter comparison -->
      <div id="recommend-box" style="display:none" class="recommend-box">
        <div class="rec-label">💡 Candidate settings for a comparison run</div>
        <div class="rec-reason" id="rec-reason">--</div>
        <div class="rec-params" id="rec-params"></div>
        <button class="rec-apply" id="rec-apply-btn" onclick="applyRecommendation()">
          ✅ Apply candidate settings via MQTT
        </button>
      </div>

      <!-- 4. Manual PID settings for a new experiment -->
      <div class="pid-tuner-box">
        <div class="pt-header">
          <span class="pt-title">🎛️ PID settings · MQTT command delivery</span>
          <div class="pt-preset-row">
            <button class="pt-preset-btn" onclick="setPidPreset(0.45, 0.015, 0.03)">Default PID</button>
            <button class="pt-preset-btn" onclick="setPidPreset(0.20, 0.005, 0.01)">Weak response</button>
            <button class="pt-preset-btn" onclick="setPidPreset(1.20, 0.040, 0.08)">Strong correction</button>
          </div>
        </div>
        <div class="pt-grid">
          <div class="pt-field">
            <label>Kp (proportional)</label>
            <input type="number" id="tune-kp" step="0.05" min="0" max="10" value="0.45">
          </div>
          <div class="pt-field">
            <label>Ki (integral)</label>
            <input type="number" id="tune-ki" step="0.005" min="0" max="2" value="0.015">
          </div>
          <div class="pt-field">
            <label>Kd (derivative)</label>
            <input type="number" id="tune-kd" step="0.005" min="0" max="1" value="0.03">
          </div>
        </div>
        <button class="btn-dispatch-pid" id="btn-dispatch-pid" onclick="dispatchTunedPid()">
          🚀 Send settings via MQTT and run
        </button>
      </div>

      <!-- 5. Simulation fault experiment -->
      <div class="fault-inject">
        <div class="fi-title">🧪 Teaching experiment: simulated drive fault</div>
        <label class="fi-toggle" id="fi-mismatch-label">
          <input type="checkbox" id="fi-mismatch" onchange="onFaultChange()">
          Reduce simulated left-wheel response by 20% (factor = 0.8)
        </label>
        <div style="font-size:10px;color:var(--text-muted);margin-top:4px">
          This checkbox configures the next run. Click Run to apply it. L5 computes residuals; L6 requires enough consecutive observations. Clearing a simulation fault does not repair a physical motor.
        </div>
      </div>
      <div class="twin-command" id="l6-command" role="status">After submitting a command, wait for the source acknowledgement.</div>
    </div>`;
}

function renderL6Feedback(data) {
  const findings = data.metrics?.findings ?? [];
  const rec = data.metrics?.recommendation;

  // Toggle remedy-box based on drive issue finding or fault
  const hasDriveIssue = data.quality === 'good' && findings.some(f => f.code && f.code.startsWith('drive_'));
  const remedyBox = document.getElementById('remedy-box');
  if (remedyBox) remedyBox.style.display = hasDriveIssue ? '' : 'none';

  const fl = document.getElementById('findings-list');
  if (fl) {
    if (!findings.length) {
      fl.innerHTML = '<div style="font-size:11px;color:var(--text-muted)">No significant anomaly observed in the current condition</div>';
    } else {
      fl.innerHTML = findings.map(f => {
        const cls = f.severity === 'warning' ? 'warning' : f.severity === 'error' ? 'error' : f.code === 'normal' ? 'ok' : 'info';
        return `<div class="finding-card ${cls}">
          <div class="fc-title">${f.title}</div>
          <div class="fc-evidence">${(f.evidence||[]).join(' · ')}</div>
          ${f.advice ? `<div style="font-size:10px;color:var(--text-muted);margin-top:2px">Advice: ${f.advice}</div>` : ''}
        </div>`;
      }).join('');
    }
  }

  const rb = document.getElementById('recommend-box');
  if (rb) {
    if (rec) {
      rb.style.display = '';
      const rr = document.getElementById('rec-reason');
      if (rr) rr.textContent = rec.reason ?? '';
      const rp = document.getElementById('rec-params');
      if (rp && rec.config) {
        const cfg = rec.config;
        rp.innerHTML = ['Kp','Ki','Kd'].map(k => `
          <div class="rec-param">
            <div class="pname">${k}</div>
            <div class="pval">${cfg[k] ?? '--'}</div>
          </div>`).join('');
      }
    } else {
      rb.style.display = 'none';
    }
  }
  const commandEl = document.getElementById('l6-command');
  if (commandEl && State.pendingCommand) commandEl.textContent =
    data.command?.command_id === State.pendingCommand.id ? data.command.message : State.pendingCommand.message;
}

async function applyRecommendation() {
  const btn = document.getElementById('rec-apply-btn');
  if (btn) { btn.disabled = true; btn.textContent = 'Sending command…'; }
  try {
    const result = await CtrlBar.send('recommend');
    if (btn) btn.textContent = result ? 'Submitted; awaiting source acknowledgement' : State.pendingCommand.message;
  } catch (e) {
    if (btn) btn.textContent = '❌ Request failed';
  }
  setTimeout(() => { if (btn) { btn.disabled = false; btn.textContent = '✅ Apply candidate settings via MQTT'; } }, 2000);
}

function onFaultChange() {
  State.faultMismatch = document.getElementById('fi-mismatch')?.checked ?? false;
  const lbl = document.getElementById('fi-mismatch-label');
  if (lbl) lbl.classList.toggle('active', State.faultMismatch);
}

/* ─── Code Loading ─── */
async function loadCode(layer, filename) {
  const cacheKey = `${layer.key}/${filename}`;
  let text = State.codeCache[cacheKey];
  if (!text) {
    try {
      const r = await fetch(`/api/code/${layer.key}/${filename}`);
      text = r.ok ? await r.text() : `# Cannot read ${filename}`;
    } catch (_) {
      text = `# Read failed`;
    }
    State.codeCache[cacheKey] = text;
  }
  State.activeTab[layer.id] = filename;

  const scroll = document.getElementById('code-scroll');
  if (!scroll) return;
  scroll.innerHTML = `<pre class="language-python"><code class="language-python">${escHtml(text)}</code></pre>`;
  if (window.Prism) Prism.highlightAllUnder(scroll);

  highlightFocus(layer, text);
}

function highlightFocus(layer, text) {
  const scroll = document.getElementById('code-scroll');
  if (!scroll) return;
  const pre = scroll.querySelector('pre');
  if (!pre) return;
  const lines = text.split('\n');
  const focusFn = layer.focusFn;
  let focusLine = -1;
  lines.forEach((l, i) => { if (l.includes(`def ${focusFn}`)) focusLine = i; });
  if (focusLine < 0) return;

  const codeEl = pre.querySelector('code');
  const rawLines = codeEl.innerHTML.split('\n');
  codeEl.innerHTML = rawLines.map((l, i) => {
    if (i === focusLine) return `<span class="hl-line" id="hl-focus">${l}</span>`;
    return l;
  }).join('\n');

  setTimeout(() => {
    const hl = document.getElementById('hl-focus');
    if (hl) hl.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, 100);
}

async function switchTab(layerId, filename, btn) {
  document.querySelectorAll('.cs-tab').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  const layer = LAYER_BY_ID[layerId];
  await loadCode(layer, filename);
}

function setCodeMode(mode, btn) {
  State.codeMode = mode;
  document.querySelectorAll('.mode-toggle button').forEach(b => b.classList.remove('on'));
  btn.classList.add('on');
}

/* ─── Dashboard Rendering ─── */
function renderLayerDash(data, layer) {
  layer.kpis.forEach((kpi, i) => {
    const el = document.getElementById(`kpi-${layer.id}-${i}`);
    if (!el) return;
    const val = kpi.key(data);
    el.innerHTML = `${val}<span class="kpi-unit">${kpi.unit}</span>`;
  });

  if (layer.id === 2 && data.frame?.sensors) {
    data.frame.sensors.forEach((v, i) => {
      const el = document.getElementById(`led-${i}`);
      if (el) el.classList.toggle('on', !!v);
    });
  }

  // L3 MQTT Inspector Updates
  if (layer.id === 3 && data.mqtt) {
    const m = data.mqtt;
    const tTel = document.getElementById('mqtt-topic-telemetry');
    const tCmd = document.getElementById('mqtt-topic-command');
    if (tTel && m.prefix) tTel.textContent = `${m.prefix}/telemetry`;
    if (tCmd && m.prefix) tCmd.textContent = `${m.prefix}/command`;

    const pv = document.getElementById('packet-json');
    if (pv && data.frame) {
      const packetPreview = {
        topic: `${m.prefix}/telemetry`,
        qos: 1,
        seq: data.frame.seq,
        source_time_s: data.frame.t_sim_s,
        left_speed_mps: data.frame.left_speed_mps,
        right_speed_mps: data.frame.right_speed_mps,
        uL: data.frame.uL,
        uR: data.frame.uR,
        sensors: data.frame.sensors,
        stop_reason: data.frame.stop_reason
      };
      pv.textContent = JSON.stringify(packetPreview, null, 2);
    }

    const btnUp = document.getElementById('btn-toggle-upload');
    const stUp  = document.getElementById('status-upload');
    if (btnUp && stUp) {
      btnUp.className = `c-switch-btn ${m.upload ? 'on' : 'off'}`;
      stUp.textContent = m.upload ? 'Enabled' : 'Interrupted; telemetry paused';
    }

    const btnFb = document.getElementById('btn-toggle-feedback');
    const stFb  = document.getElementById('status-feedback');
    if (btnFb && stFb) {
      btnFb.className = `c-switch-btn ${m.feedback ? 'on' : 'off'}`;
      stFb.textContent = m.feedback ? 'Enabled' : 'Interrupted';
    }
  }

  updateChart(data, layer);
  if (layer.id === 5) renderL5Workbench(data);

  const st = layer.statusFn(data);
  const tw = document.getElementById('status-tag-wrap');
  if (tw) tw.innerHTML = `<span class="status-tag ${st.cls}">${st.text}</span>`;
  const sm = document.getElementById('status-msg');
  if (sm) sm.textContent = layer.id === 5
    ? 'L5 provides healthy references and deviation evidence. L6 requires a sufficient consecutive window. Speed residuals alone cannot establish a mechanical or electrical cause.'
    : data.metrics?.message ?? '';

  const el = document.getElementById('event-log');
  if (el && data.events) {
    el.innerHTML = data.events.slice(-6).reverse().map(e =>
      `<div class="ev-line"><span>${e.time}</span>${e.text}</div>`).join('');
  }

  if (layer.id === 6) renderL6Feedback(data);

  if (State.codeMode === 'follow' && data.source_state === 'running') {
    const hl = document.getElementById('hl-focus');
    if (hl) hl.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
}

/* ─── Canvas Chart ─── */
function updateChart(data, layer) {
  const canvas = document.getElementById(`layer-chart-${layer.id}`);
  if (!canvas) return;
  if (layer.id === 5) { drawTwinResiduals(data, canvas); return; }

  if (!State.chartBuffers[layer.id]) State.chartBuffers[layer.id] = [];
  const buf = State.chartBuffers[layer.id];

  let val = null;
  if (layer.id === 3) {
    val = data.mqtt?.sent ?? null;
  } else if (layer.chartKey && data.frame) {
    val = data.frame[layer.chartKey] ?? null;
  } else if (layer.chartKey && data.history?.length) {
    val = data.history[data.history.length - 1]?.[layer.chartKey] ?? null;
  }

  if (val !== null) {
    const t = data.source_time_s ?? 0;
    buf.push({ t, v: val });
    if (buf.length > 100) buf.shift();
  }

  if (buf.length < 2) return;

  canvas.width  = canvas.offsetWidth;
  canvas.height = canvas.offsetHeight;
  const ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  const PAD = { l: 36, r: 10, t: 8, b: 18 };
  const cW = W - PAD.l - PAD.r;
  const cH = H - PAD.t - PAD.b;

  ctx.clearRect(0, 0, W, H);

  const vals = buf.map(d => d.v);
  let minV = Math.min(...vals), maxV = Math.max(...vals);
  if (Math.abs(maxV - minV) < 1e-6) { minV -= 0.01; maxV += 0.01; }

  const toX = i => PAD.l + (i / (buf.length - 1)) * cW;
  const toY = v => PAD.t + (1 - (v - minV) / (maxV - minV)) * cH;

  ctx.strokeStyle = 'rgba(255,255,255,0.05)';
  ctx.lineWidth = 1;
  [0, 0.5, 1].forEach(ratio => {
    const y = PAD.t + ratio * cH;
    ctx.beginPath(); ctx.moveTo(PAD.l, y); ctx.lineTo(W - PAD.r, y); ctx.stroke();
  });

  const grad = ctx.createLinearGradient(0, PAD.t, 0, H - PAD.b);
  grad.addColorStop(0, layer.color + '33');
  grad.addColorStop(1, layer.color + '00');
  ctx.beginPath();
  ctx.moveTo(toX(0), toY(buf[0].v));
  buf.forEach((d, i) => ctx.lineTo(toX(i), toY(d.v)));
  ctx.lineTo(toX(buf.length-1), H - PAD.b);
  ctx.lineTo(toX(0), H - PAD.b);
  ctx.closePath();
  ctx.fillStyle = grad; ctx.fill();

  ctx.beginPath();
  ctx.moveTo(toX(0), toY(buf[0].v));
  buf.forEach((d, i) => ctx.lineTo(toX(i), toY(d.v)));
  ctx.strokeStyle = layer.color; ctx.lineWidth = 1.5; ctx.stroke();

  const lx = toX(buf.length-1), ly = toY(buf[buf.length-1].v);
  ctx.beginPath(); ctx.arc(lx, ly, 3, 0, Math.PI*2);
  ctx.fillStyle = '#fff'; ctx.fill();

  ctx.fillStyle = 'rgba(255,255,255,0.35)'; ctx.font = '10px monospace';
  ctx.textAlign = 'right';
  ctx.fillText(maxV.toFixed(2), PAD.l - 3, PAD.t + 9);
  ctx.fillText(minV.toFixed(2), PAD.l - 3, H - PAD.b);
}

function escHtml(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

document.addEventListener('DOMContentLoaded', () => {
  buildHomePage();
  CtrlBar.init();
  Poller.start();
  Router.init();
});


/* ─── L6 Actionable Handlers ─── */
function setPidPreset(kp, ki, kd) {
  const ekp = document.getElementById('tune-kp');
  const eki = document.getElementById('tune-ki');
  const ekd = document.getElementById('tune-kd');
  if (ekp) ekp.value = kp;
  if (eki) eki.value = ki;
  if (ekd) ekd.value = kd;
}

async function dispatchTunedPid() {
  const kp = parseFloat(document.getElementById('tune-kp')?.value || 0.45);
  const ki = parseFloat(document.getElementById('tune-ki')?.value || 0.015);
  const kd = parseFloat(document.getElementById('tune-kd')?.value || 0.03);
  const btn = document.getElementById('btn-dispatch-pid');
  if (btn) { btn.disabled = true; btn.textContent = '📡 Sending via MQTT…'; }

  const data = State.apiData;
  let cfg = {};
  if (data?.frame?.config) Object.assign(cfg, data.frame.config);
  else cfg = { speed: 4.0, environment_level: 1, environment_seed: 7, dropout: false };
  cfg.Kp = kp; cfg.Ki = ki; cfg.Kd = kd;
  cfg.motor_left_factor = State.faultMismatch ? 0.8 : 1.0;

  try {
    const res = await fetch('/api/command', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'run', config: cfg }),
    });
    const result = await res.json();
    State.pendingCommand = {id:result.command_id, message:res.ok ? 'Submitted; awaiting source acknowledgement' : result.error};
    if (btn) btn.textContent = State.pendingCommand.message;
  } catch (_) {
    if (btn) btn.textContent = '❌ Network request failed';
  }
  setTimeout(() => {
    if (btn) { btn.disabled = false; btn.textContent = '🚀 Send settings via MQTT and run'; }
  }, 1600);
}

async function remedyMotorFault() {
  State.faultMismatch = false;
  const chk = document.getElementById('fi-mismatch');
  if (chk) chk.checked = false;
  const lbl = document.getElementById('fi-mismatch-label');
  if (lbl) lbl.classList.remove('active');
  const rem = document.getElementById('remedy-box');
  if (rem) rem.style.display = 'none';

  const data = State.apiData;
  let cfg = {};
  if (data?.frame?.config) Object.assign(cfg, data.frame.config);
  cfg.motor_left_factor = 1.0;

  await CtrlBar.send('run', cfg);
}

async function retestBenchmark() {
  State.faultMismatch = false;
  const chk = document.getElementById('fi-mismatch');
  if (chk) chk.checked = false;
  const lbl = document.getElementById('fi-mismatch-label');
  if (lbl) lbl.classList.remove('active');

  const defaultCfg = {
    Kp: 0.45, Ki: 0.015, Kd: 0.03,
    speed: 4.0, environment_level: 1, environment_seed: 7,
    motor_left_factor: 1.0, dropout: false
  };
  setPidPreset(0.45, 0.015, 0.03);
  await CtrlBar.send('run', defaultCfg);
}
