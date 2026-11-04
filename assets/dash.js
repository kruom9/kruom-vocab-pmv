(function(){'use strict';
// Executive (whole school) + per-class dashboard. Auth = teacher code (same session as teacher.html). Read-only RPC vocab_dash.
const $=s=>document.querySelector(s),A=()=>$('#app');
const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function rpc(fn,a){let r;try{r=await fetch(VCFG.url+'/rest/v1/rpc/'+fn,{method:'POST',headers:{apikey:VCFG.key,'Content-Type':'application/json'},body:JSON.stringify(a||{})})}catch(e){throw new Error('เชื่อมต่อไม่ได้')}
  let d=null;try{d=await r.json()}catch(e){}if(!r.ok){const m=(d&&d.message)||'ERROR';const e=new Error(m.includes('NO_SESSION')?'หมดเวลา กรุณาเข้าสู่ระบบใหม่':m.includes('LOCKED')?'ใส่ผิดหลายครั้ง รอ 10 นาที':m);e.code=m;throw e}
  if(d&&d.error)throw new Error(d.error==='BAD_LOGIN'?'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง':d.error);return d}
let TOK=sessionStorage.getItem('kv2_t'),D=null,SEL=new URLSearchParams(location.search).get('c')||'all';
const bkk=iso=>iso?new Date(iso).toLocaleString('th-TH',{timeZone:'Asia/Bangkok',day:'numeric',month:'short',year:'2-digit',hour:'2-digit',minute:'2-digit'})+' น.':'-';
const hh=h=>String(h).padStart(2,'0')+':00';
const peak=u=>u.peak_date?`${new Date(u.peak_date+'T12:00:00+07:00').toLocaleDateString('th-TH',{timeZone:'Asia/Bangkok',weekday:'short',day:'numeric',month:'short'})} ${hh(u.peak_hour)}–${hh(u.peak_hour+1)} น. (${u.peak_n} ครั้ง)`:'-';
function login(msg){A().innerHTML=`<div class="hero"><div class="pump">📊</div><h1>Dashboard ผู้บริหาร / ห้องเรียน</h1><div class="sub">Word Quest · โรงเรียนปิยมิตรวิทยา ฝ่ายมัธยม</div></div><div class="card" style="max-width:420px;margin:auto"><form id="f"><label for="u" style="display:block;font-size:14px;margin:0 0 4px;color:var(--gold)">ชื่อผู้ใช้</label><input id="u" type="text" placeholder="ชื่อผู้ใช้" autocomplete="username" autocapitalize="none" autocorrect="off" spellcheck="false"><div class="mut" style="font-size:13px;margin:-4px 0 8px">ครูประจำชั้นเว้นว่างชื่อผู้ใช้ได้</div><label for="c" style="display:block;font-size:14px;margin:0 0 4px;color:var(--gold)">รหัสผ่าน</label><input id="c" type="password" placeholder="รหัสผ่าน" autocomplete="current-password" required><div class="err" id="e">${esc(msg||'')}</div><button class="btn">เข้าสู่ระบบ</button></form></div>`;
  $('#f').onsubmit=async ev=>{ev.preventDefault();try{const d=await rpc('vocab_teacher_login',{p_user:$('#u').value.trim()||null,p_code:$('#c').value});TOK=d.token;sessionStorage.setItem('kv2_t',TOK);load()}catch(e){$('#e').textContent=e.message}}}
async function load(){const [g,r]=SEL==='all'?[null,null]:SEL.split('/').map(Number);
  try{D=await rpc('vocab_dash',{p_token:TOK,p_grade:g,p_room:r});render()}catch(e){if(/NO_SESSION/.test(e.code)){sessionStorage.removeItem('kv2_t');TOK=null;login(e.message)}else alert(e.message)}}
function ucard(cls,title,u,emptyTxt){
  if(!u)return `<div class="card ${cls}"><h3>${title}</h3><div class="mut">${emptyTxt}</div></div>`;
  const never=u.attempts===0;
  return `<div class="card ${cls}" id="${cls.slice(1)}"><h3>${title}</h3><div class="nm">${esc(u.name)}</div><div class="mut">ม.${u.g}/${u.r} · เลขที่ ${u.no} · รหัส ${esc(u.code)}</div>
  <table><tr><th>เลเวล</th><td>${u.level}</td></tr><tr><th>จำนวนครั้งที่เล่น</th><td>${never?'<span class="no">ยังไม่เคยเล่น</span>':u.attempts+' ครั้ง'}</td></tr>
  <tr><th>แต้ม / ดาว</th><td>${u.points} / ${u.stars}⭐</td></tr><tr><th>เวลา (กิจกรรมล่าสุด)</th><td>${never?'ยังไม่เคยเล่น':bkk(u.last_at)}</td></tr><tr><th>ช่วงพีค</th><td>${never?'ยังไม่เคยเล่น':peak(u)}</td></tr></table></div>`}
function render(){const S=D.scope,sm=D.summary,ex=S.role==='exec';
  const title=S.grade?`ห้อง ม.${S.grade}/${S.room}`:'ทั้งโรงเรียน';
  const mx=Math.max(1,...D.peak_hours.map(x=>x[1])),hm=Object.fromEntries(D.peak_hours);
  const bars=[...Array(24).keys()].filter(h=>h>=6&&h<=23||hm[h]).map(h=>`<div style="height:${Math.round((hm[h]||0)/mx*100)}%" title="${hh(h)} · ${hm[h]||0} ครั้ง"><span>${h}</span></div>`).join('');
  A().innerHTML=`<div class="row" style="justify-content:space-between"><h1>📊 ${ex?'Dashboard ผู้บริหาร':'Dashboard ห้องเรียน'} · <span id="ttl">${title}</span></h1><div class="row">${ex?'<a class="btn sec" href="teacher.html">Dashboard ครู</a>':''}<button class="btn sec" id="lo">ออกจากระบบ</button></div></div>
  <div class="card row"><label>มุมมอง <select id="cs" ${ex?'':'disabled'}>${ex?'<option value="all">ทั้งโรงเรียน (ผู้บริหาร)</option>':''}${D.classes.map(c=>{const v=c.g+'/'+c.r;return `<option value="${v}" ${(S.grade+'/'+S.room)===v?'selected':''}>ม.${v}</option>`}).join('')}</select></label>
  <button class="btn" id="rf">↻ รีเฟรช</button><span class="mut">ผู้ใช้: ${esc(S.name)} (${ex?'ผู้บริหาร – ดูได้ทุกห้อง':'ครูประจำห้อง – ดูได้เฉพาะห้องนี้'}) · ข้อมูล ณ ${bkk(D.now)}</span></div>
  <div class="kp"><div class="card">นักเรียน<br><b id="k1">${sm.students}</b></div><div class="card">เคยเล่นแล้ว<br><b>${sm.played}</b></div><div class="card">ยังไม่เคยเล่น<br><b>${sm.never}</b></div><div class="card">จำนวนครั้งที่เล่นรวม<br><b>${sm.attempts}</b></div><div class="card">เลเวลเฉลี่ย<br><b>${sm.avg_level}</b></div></div>
  <div class="uc">${ucard('utop','🥇 ผู้ใช้งานสูงสุด',D.top,'ยังไม่มีใครเล่น')}${ucard('ulow','🔻 ผู้ใช้งานต่ำสุด',D.low,'ไม่มีนักเรียน')}</div>
  <div class="card"><h2>ช่วงเวลาที่เล่น (ชั่วโมง, เวลาไทย)</h2><div class="bars">${bars}</div><div style="height:20px"></div></div>
  ${ex&&!S.grade?`<div class="card" style="overflow:auto"><h2>สรุปรายห้อง</h2><table><tr><th>ห้อง</th><th>นักเรียน</th><th>เคยเล่น</th><th>ครั้งที่เล่นรวม</th><th>เลเวลเฉลี่ย</th></tr>${D.per_class.map(c=>`<tr><td><a href="#" data-c="${c.g}/${c.r}">ม.${c.g}/${c.r}</a></td><td>${c.students}</td><td>${c.played}</td><td>${c.attempts}</td><td>${c.avg_level}</td></tr>`).join('')}</table></div>`:''}
  <div class="card"><h2>นิยามที่ใช้</h2><div class="def" id="def">${esc(D.definition)}</div></div>`;
  $('#lo').onclick=()=>{sessionStorage.removeItem('kv2_t');TOK=null;login()};$('#rf').onclick=load;
  $('#cs').onchange=e=>{SEL=e.target.value;load()};
  A().querySelectorAll('[data-c]').forEach(a=>a.onclick=ev=>{ev.preventDefault();SEL=a.dataset.c;load()});
}
if(TOK)load();else login();
})();
