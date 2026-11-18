'use strict';
const $ = id => document.getElementById(id);
let state = null, meta = null, polling = false, toastTimer;
const trackImage = new Image(); trackImage.src = '/api/map';
const colors = {ink:'#173236', teal:'#087e76', orange:'#d98b3a', blue:'#607bad', muted:'#81908b', grid:'#edf0ed'};
const fmt = (value, digits=2) => Number.isFinite(value) ? value.toFixed(digits) : '—';
const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

function toast(text) {
  $('toast').textContent = text; $('toast').hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => {$('toast').hidden = true;}, 4500);
}
async function post(path, payload) {
  const response = await fetch(path, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'Request failed');
  return result;
}
function configFromForm() {
  return {Kp:Number($('Kp').value),Ki:Number($('Ki').value),Kd:Number($('Kd').value),
    environment_level:Number($('environment').value),environment_seed:Number($('seed').value),
    speed:Number($('speed').value),dropout:$('dropout').checked,motor_left_factor:$('mismatch').checked ? .8 : 1};
}
async function command(action, config=null) {
  try { await post('/api/command',{action,config}); await refresh(); }
  catch(error) {toast(error.message);}
}
document.querySelectorAll('.tab').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('.tab').forEach(tab => tab.classList.toggle('active', tab === button));
  document.querySelectorAll('.view').forEach(view => view.classList.toggle('active',view.id === 'view-'+button.dataset.view));
  redraw();
}));
document.querySelectorAll('.preset').forEach(button => button.addEventListener('click', () => {
  const values = {default:[.45,.015,.03],weak:[.05,0,0],strong:[15,0,0]}[button.dataset.preset];
  ['Kp','Ki','Kd'].forEach((key,i) => {$(key).value = values[i];});
  document.querySelectorAll('.preset').forEach(item => item.classList.toggle('selected', item === button));
}));
$('run').addEventListener('click', () => command('run', configFromForm()));
$('pause').addEventListener('click', () => command(state?.source_state === 'paused' ? 'resume' : 'pause'));
$('step').addEventListener('click', () => command('step'));
$('reset').addEventListener('click', () => command('reset'));
$('recommend').addEventListener('click', () => {
  if (!state?.metrics.recommendation || state.quality !== 'good') return;
  ['Kp','Ki','Kd'].forEach((key,i) => {$(key).value = [.45,.015,.03][i];});
  document.querySelectorAll('.preset').forEach(item => item.classList.toggle('selected', item.dataset.preset === 'default'));
  command('recommend');
});
[['upload-toggle','upload'],['feedback-toggle','feedback']].forEach(([id,channel]) => {
  $(id).addEventListener('change', async event => {
    try {await post('/api/transport',{channel,enabled:event.target.checked});await refresh();}
    catch(error) {toast(error.message);await refresh();}
  });
});

function canvasContext(id) {
  const canvas = $(id), rect = canvas.getBoundingClientRect();
  if (rect.width < 1 || rect.height < 1) return null;
  const ratio = window.devicePixelRatio || 1;
  const width = Math.round(rect.width*ratio), height = Math.round(rect.height*ratio);
  if(canvas.width !== width || canvas.height !== height) {canvas.width = width;canvas.height = height;}
  const ctx = canvas.getContext('2d');ctx.setTransform(ratio,0,0,ratio,0,0);ctx.clearRect(0,0,rect.width,rect.height);
  return {ctx,w:rect.width,h:rect.height};
}
function drawTrack() {
  const surface = canvasContext('track');if(!surface || !meta || !trackImage.complete) return;
  const {ctx,w,h} = surface, pad=16;
  const scale = Math.min((w-2*pad)/meta.width,(h-2*pad)/meta.height);
  const left=(w-meta.width*scale)/2,top=(h-meta.height*scale)/2;
  const point = (x,y) => [left+x*scale,top+(meta.height-y)*scale];
  ctx.drawImage(trackImage,left,top,meta.width*scale,meta.height*scale);
  if (!state?.frame) return;
  ctx.beginPath();state.history.forEach((f,i) => {const [x,y]=point(f.x_m,f.y_m);i && !f.gap_before?ctx.lineTo(x,y):ctx.moveTo(x,y);});
  ctx.strokeStyle=colors.teal;ctx.lineWidth=2;ctx.stroke();
  const f=state.frame,[x,y]=point(f.x_m,f.y_m);
  if(state.twin?.prediction_valid) {
    const [px,py]=point(...state.twin.prior_xy);ctx.beginPath();ctx.arc(px,py,4,0,2*Math.PI);
    ctx.strokeStyle=colors.orange;ctx.lineWidth=2;ctx.stroke();
  }
  ctx.save();ctx.translate(x,y);ctx.rotate(-f.theta_rad);
  ctx.fillStyle='#087e7626';ctx.strokeStyle=colors.teal;ctx.lineWidth=1.5;
  ctx.fillRect(-.08*scale,-.05*scale,.16*scale,.1*scale);ctx.strokeRect(-.08*scale,-.05*scale,.16*scale,.1*scale);
  ctx.beginPath();ctx.moveTo(.06*scale,0);ctx.lineTo(.025*scale,-.018*scale);ctx.lineTo(.025*scale,.018*scale);ctx.closePath();ctx.fillStyle=colors.teal;ctx.fill();ctx.restore();
  f.sensor_x.forEach((sx,i) => {const [px,py]=point(sx,f.sensor_y[i]);ctx.beginPath();ctx.arc(px,py,2.2,0,2*Math.PI);ctx.fillStyle=f.sensors[i]?colors.orange:'#b8c4bf';ctx.fill();});
}
function drawSensors() {
  const surface=canvasContext('sensors');if(!surface)return;
  const {ctx,w,h}=surface, pad=22,base=h-16,plotH=h-40,unit=(w-pad-8)/8;
  ctx.font='9px sans-serif';ctx.textAlign='right';ctx.lineWidth=1;
  [0,.5,1].forEach(value=>{const y=base-value*plotH;ctx.strokeStyle=colors.grid;ctx.beginPath();ctx.moveTo(pad,y);ctx.lineTo(w,y);ctx.stroke();ctx.fillStyle=colors.muted;ctx.fillText(String(value),pad-6,y+3);});
  for(let i=0;i<8;i++) {
    const x=pad+i*unit+unit*.23,bw=unit*.54;
    const observed=state?.frame?.strengths[i]||0,ideal=state?.frame?.ideal_strengths[i]||0;
    ctx.fillStyle='#e7eeea';ctx.fillRect(x,base-plotH,bw,plotH);
    ctx.fillStyle=observed>=.5?colors.teal:'#8ab9a7';ctx.fillRect(x,base-observed*plotH,bw,observed*plotH);
    ctx.setLineDash([3,2]);ctx.strokeStyle=colors.orange;ctx.lineWidth=1.3;ctx.strokeRect(x-2,base-ideal*plotH,bw+4,ideal*plotH);ctx.setLineDash([]);
  }
}
function drawChart(id, keys, lineColors, fixedRange=null) {
  const surface=canvasContext(id);if(!surface)return;
  const {ctx,w,h}=surface,left=34,right=w-9,top=9,bottom=h-24;
  const history=state?.history||[];const tmax=Math.max(10,history.at(-1)?.t_sim_s||0);
  const largest=Math.max(.02,...history.flatMap(f=>keys.map(key=>Math.abs(f[key]))));
  const [ymin,ymax]=fixedRange||[-largest*1.2,largest*1.2];
  const py=v=>bottom-(v-ymin)/(ymax-ymin)*(bottom-top);
  ctx.font='9px sans-serif';ctx.lineWidth=1;
  [ymin,0,ymax].forEach(value=>{const y=py(value);ctx.beginPath();ctx.moveTo(left,y);ctx.lineTo(right,y);ctx.strokeStyle=colors.grid;ctx.stroke();ctx.fillStyle=colors.muted;ctx.textAlign='right';ctx.fillText(fmt(value,Math.abs(value)<.1?2:1),left-7,y+3);});
  for(let i=0;i<=4;i++){const t=i*tmax/4,x=left+i*(right-left)/4;ctx.fillStyle=colors.muted;ctx.textAlign='center';ctx.fillText(fmt(t,0),x,h-7);}
  ctx.textAlign='right';ctx.fillText('s',w-1,h-7);
  ctx.save();ctx.beginPath();ctx.rect(left,top,right-left,bottom-top);ctx.clip();
  keys.forEach((key,i)=>{ctx.beginPath();history.forEach((f,j)=>{const x=left+f.t_sim_s/tmax*(right-left),y=py(f[key]);j && !f.gap_before?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.strokeStyle=lineColors[i];ctx.lineWidth=1.35;ctx.stroke();});ctx.restore();
}
function redraw(){drawTrack();drawSensors();drawChart('error-chart',['sensor_error'],[colors.teal],[-1,1]);drawChart('pid-chart',['P','I','D'],[colors.teal,colors.orange,colors.blue]);}
function update() {
  if(!state)return;
  const f=state.frame,m=state.metrics,q=state.quality,bus=state.mqtt;
  $('connection').className='badge'+(!bus.connected?' bad':'');
  $('connection').innerHTML='<i></i>'+(!bus.connected?'MQTT disconnected':'MQTT connected');
  $('banner').hidden=q!=='stale';
  if(q==='stale')$('banner').textContent='Telemetry is stale. Charts and twin state retain the last valid observation; the source may still be running. Restore upload to resynchronize.';
  $('sim-time').innerHTML=fmt(f?.t_sim_s)+'<small>s</small>';
  $('mae').textContent=f?fmt(m.mae,3):'—';
  $('residual').innerHTML=fmt(f?m.residual:null,4)+'<small>m/s</small>';
  $('run-summary').textContent=f?.completed_lap?'Lap completed · '+fmt(f.lap_time_s)+' s':f?.config?'Environment '+f.config.environment_level+' · Seed '+f.config.environment_seed:'Waiting for vehicle data';
  const states={idle:'Ready',running:'Running',paused:'Paused',completed:'Experiment completed'};
  $('vehicle-status').textContent=q==='stale'?'Last observation stale':states[f?.source_state]||'Waiting for data';
  $('pose').textContent=`x ${fmt(f?.x_m,3)} · y ${fmt(f?.y_m,3)} · θ ${fmt(f?.theta_rad,2)} rad`;
  $('sensor-lamps').innerHTML=Array.from({length:8},(_,i)=>`<span class="${f?.sensors[i]?'on':''}">S${i+1}</span>`).join('');
  $('light').textContent=fmt(f?.light_gain);$('jitter').textContent=fmt(f?.lateral_jitter_m*1000,2)+' mm';
  $('analysis-title').textContent=q==='stale'?'Waiting to resynchronize':m.status;
  $('analysis-message').textContent=q==='stale'?'The last result is retained while data is stale. Restore upload before making parameter decisions from new observations.':m.message;
  $('diagnosis-cards').innerHTML=(m.findings||[]).map(item=>
    '<article class="diagnosis-card '+(item.severity==='info'?'info':'warning')+'">'+
    '<h3>'+escapeHtml(item.title)+'</h3><ul>'+item.evidence.map(text=>'<li>'+escapeHtml(text)+'</li>').join('')+'</ul>'+
    '<p><strong>Decision rule</strong>'+escapeHtml(item.rule)+'</p>'+
    '<p><strong>Next step</strong>'+escapeHtml(item.advice)+'</p>'+
    '<p class="diagnosis-scope">'+escapeHtml(item.scope)+'</p></article>').join('');
  $('pause').textContent=state.source_state==='paused'?'Resume':'Pause';
  const pending=state.command?.status==='pending';
  $('run').disabled=pending||!bus.connected;
  $('pause').disabled=pending||!['paused','running'].includes(state.source_state);
  $('step').disabled=pending||!['paused','running'].includes(state.source_state);
  $('reset').disabled=pending||!bus.connected;
  $('recommend').disabled=pending||q!=='good'||!m.recommendation;
  $('recommend').textContent=m.recommendation?.label||'No parameter recommendation available';
  const commandLabels={pending:'Sent · awaiting source acknowledgement',applied:'Applied at source',rejected:'Source rejected',timeout:'Acknowledgement timed out · outcome unknown',failed:'Publication failed'};
  $('command').textContent=state.command?(commandLabels[state.command.status]+' · '+state.command.command_id.slice(0,8)):'Waiting for an experiment command';
  $('source-time').textContent=fmt(state.source_time_s)+' s';
  $('broker-address').textContent=`127.0.0.1:${bus.port} · QoS 1`;
  $('message-count').textContent=bus.sent+' / '+bus.received;
  $('update-count').textContent=(state.twin?.updates||0)+' updates';
  $('innovation').textContent=state.twin?.prediction_valid
    ? 'Position correction '+fmt(state.twin.innovation_m*1000,3)+' mm'
    : 'Reference aligned · waiting for consecutive samples';
  $('flow-status').textContent=q==='stale'?'Data stale':m.status;
  $('data-quality').textContent={waiting:'Waiting for data',good:'Fresh data',stale:'Data stale'}[q];
  $('data-quality').className='badge'+(q==='stale'?' warn':'');
  $('upload-toggle').checked=bus.upload;$('feedback-toggle').checked=bus.feedback;
  $('gap-count').textContent=bus.gaps;$('duplicate-count').textContent=bus.duplicates;$('reject-count').textContent=bus.rejected;
  $('data-age').textContent=fmt(state.age_s,2)+' s';
  $('topic').textContent=bus.prefix+'/telemetry';
  if(f) $('payload').textContent=JSON.stringify({asset:'car01',run_id:f.run_id,seq:f.seq,t_sim_s:f.t_sim_s,
    strengths:f.strengths.map(v=>Number(v.toFixed(3))),uL:f.uL,uR:f.uR,left_speed_mps:f.left_speed_mps,
    right_speed_mps:f.right_speed_mps,stop_reason:f.stop_reason,sent_utc:f.sent_utc},null,2);
  $('records-table').innerHTML=state.records.length?'<table><thead><tr><th>Run ID</th><th>PID</th><th>Environment / Seed</th><th>Result</th></tr></thead><tbody>'+state.records.map(r=>'<tr><td>'+escapeHtml(r.run_id)+'</td><td>'+[r.config.Kp,r.config.Ki,r.config.Kd].join(' / ')+'</td><td>'+r.config.environment_level+' / '+r.config.environment_seed+'</td><td>'+(r.completed_lap?fmt(r.lap_time_s)+' s lap completed':fmt(r.end_time_s)+' s · '+({1:'Line-loss stop',2:'Out-of-bounds stop',4:'Time limit reached'}[r.stop_reason]||'Completed'))+'</td></tr>').join('')+'</tbody></table>':'<div class="empty">Completed experiments appear here. You can also export received data during a run.</div>';
  $('event-list').innerHTML=state.events.slice().reverse().map(e=>'<div><time>'+escapeHtml(e.time)+'</time>'+escapeHtml(e.text)+'</div>').join('');
  redraw();
}
async function refresh() {
  if(polling)return;polling=true;
  try {const response=await fetch('/api/state',{cache:'no-store'});if(!response.ok)throw new Error('Service unavailable');state=await response.json();update();}
  catch(error){$('connection').textContent='Web service disconnected';$('connection').className='badge bad';}
  finally{polling=false;}
}
fetch('/api/meta').then(r=>r.json()).then(value=>{meta=value;redraw();}).catch(()=>toast('Could not load map metadata. Check the Python service.'));
trackImage.onload=redraw;window.addEventListener('resize',redraw);
refresh();setInterval(refresh,250);
