(function(){
'use strict';
const V=window.VOCAB,W={};V.words.forEach(w=>W[w.w]=w);
const LV={};V.levels.forEach(l=>LV[l.n]=l);
const $=s=>document.querySelector(s),app=()=>$('#app');
const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const LS={get:(k,d)=>{try{const v=localStorage.getItem(k);return v==null?d:JSON.parse(v)}catch(e){return d}},set:(k,v)=>{try{localStorage.setItem(k,JSON.stringify(v))}catch(e){}},del:k=>{try{localStorage.removeItem(k)}catch(e){}}};
const ERR={BAD_LOGIN:'เลขประจำตัวนักเรียนหรือเลขบัตรประชาชนไม่ถูกต้อง',NO_NID:'ยังไม่มีข้อมูลเลขบัตรของนักเรียนคนนี้ กรุณาแจ้งครู',NID_FORMAT:'เลขบัตรประชาชนต้องมี 13 หลัก',LOCKED:'ใส่ผิดหลายครั้ง กรุณารอสักครู่แล้วลองใหม่',NO_SESSION:'หมดเวลาเข้าสู่ระบบ กรุณาเข้าสู่ระบบใหม่',MUST_CHANGE_PASSWORD:'กรุณาตั้งรหัสผ่านใหม่ก่อนเล่น',TOO_SHORT:'รหัสผ่านใหม่ต้องยาวอย่างน้อย 6 ตัว',SAME_AS_INITIAL:'รหัสใหม่ต้องไม่ซ้ำรหัสเริ่มต้น',BAD_OLD:'รหัสผ่านเดิมไม่ถูกต้อง',ALREADY_TODAY:'ด่านนี้เล่นไปแล้ววันนี้ มาเล่นใหม่พรุ่งนี้นะ',LEVEL_LOCKED:'ด่านนี้ยังไม่เปิด',BAD_RESULTS:'ข้อมูลไม่ถูกต้อง',NO_STUDENT:'ไม่พบเลขประจำตัวนี้ในระบบ ตรวจสอบเลข 5 หลักอีกครั้ง ถ้ายังเข้าไม่ได้ให้แจ้งครู',NETWORK:'เชื่อมต่ออินเทอร์เน็ตไม่ได้ ลองใหม่อีกครั้ง'};
async function rpc(fn,args,opt){
  let res;
  try{res=await fetch(VCFG.url+'/rest/v1/rpc/'+fn,Object.assign({method:'POST',headers:{apikey:VCFG.key,'Content-Type':'application/json'},body:JSON.stringify(args||{})},opt||{}))}
  catch(e){const er=new Error(ERR.NETWORK);er.code='NETWORK';throw er}
  let d=null;try{d=await res.json()}catch(e){}
  if(!res.ok){const m=(d&&d.message)||'ERROR';const c=Object.keys(ERR).find(k=>m.indexOf(k)>=0)||m;const er=new Error(ERR[c]||('เกิดข้อผิดพลาด: '+m));er.code=c;throw er}
  if(d&&d.error){const er=new Error(ERR[d.error]||d.error);er.code=d.error;er.data=d;throw er}
  return d;
}
let TOK=LS.get('kv2_tok',null),ME=null;
// login-only (v4): retired guest / old-system local data never grants access
['kv2_guest','kv_token','kv_pending'].forEach(k=>LS.del(k));
if(typeof TOK!=='string'||!TOK){TOK=null;LS.del('kv2_tok')}
{const ip=LS.get('kv2_ip',null);if(ip&&(!ip.tok||ip.tok!==TOK))LS.del('kv2_ip');LS.set('kv2_q',LS.get('kv2_q',[]).filter(j=>j&&j.tok))}
function dropSession(){TOK=null;ME=null;LS.del('kv2_tok');LS.del('kv2_me');LS.del('kv2_ip')}
// ---------- TTS ----------
let VOICE=null;
function pickVoice(){if(!('speechSynthesis' in window))return;const vs=speechSynthesis.getVoices();VOICE=vs.find(v=>/en[-_]US/i.test(v.lang))||vs.find(v=>/en[-_]GB/i.test(v.lang))||vs.find(v=>/^en/i.test(v.lang))||null}
if('speechSynthesis' in window){pickVoice();speechSynthesis.onvoiceschanged=pickVoice}
function say(t,rate){if(!('speechSynthesis' in window))return;try{speechSynthesis.cancel();const u=new SpeechSynthesisUtterance(t);u.lang=VOICE?VOICE.lang:'en-US';if(VOICE)u.voice=VOICE;u.rate=rate||.9;speechSynthesis.speak(u)}catch(e){}}
// ---------- helpers ----------
const shuffle=a=>{a=a.slice();for(let i=a.length-1;i>0;i--){const j=Math.random()*(i+1)|0;[a[i],a[j]]=[a[j],a[i]]}return a};
const img=w=>'img/w/'+W[w].img+'.webp';
const starsTxt=n=>'★'.repeat(n)+'☆'.repeat(3-n);
const digits=s=>String(s||'').replace(/[๐-๙]/g,d=>'๐๑๒๓๔๕๖๗๘๙'.indexOf(d)).replace(/[^0-9]/g,'');
const today=()=>new Date(Date.now()+7*3600e3).toISOString().slice(0,10);
function conflict(a,b){return (V.conflicts||[]).some(g=>g.includes(a)&&g.includes(b))}
// difficulty curve: more choices, more listening, later Thai-meaning/sentence questions
function cfg(n){return {opts:n<=2?3:4,listen:n===1?0:n===2?3:n<=4?5:6}}
function distract(n,w,k,pic){
  const lv=LV[n],pool=shuffle(lv.pool.filter(x=>x!==w));
  const band=shuffle(V.words.filter(x=>x.lv===W[w].lv&&x.w!==w).map(x=>x.w));
  const out=[];for(const x of pool.concat(band)){if(out.length>=k)break;if(out.includes(x)||conflict(w,x))continue;if(pic&&!W[x].img)continue;out.push(x)}
  return out;
}
function buildLevel(n){
  const l=LV[n],c=cfg(n),miss=LS.get('kv2_miss',[]);
  let ws=shuffle(l.pool);ws.sort((a,b)=>(l.new.includes(b)?1:0)+(miss.includes(b)?1:0)-((l.new.includes(a)?1:0)+(miss.includes(a)?1:0)));
  ws=shuffle(ws.slice(0,15));
  let nl=0;
  return ws.map(w=>{const x=W[w];let t;
    if(x.img){t=(nl<c.listen&&Math.random()<.6)?'listen':'pic';if(t==='listen')nl++}else t=x.cl&&Math.random()<.5?'cloze':'th';
    const pic=t==='listen';return {w,t,o:shuffle([w].concat(distract(n,w,c.opts-1,pic)))}});
}
// ---------- screens ----------
function shell(h){app().innerHTML=h;window.scrollTo(0,0)}
function hero(sub){return `<div class="hero"><div class="pump">🎃</div><h1>Word Quest</h1><div style="font-weight:600">ศัพท์สนุก · Halloween</div><div class="sub">โรงเรียนปิยมิตรวิทยา ฝ่ายมัธยม${sub?'<br>'+sub:''}</div></div>`}
async function start(){
  flush();
  if(!TOK)return login();   // no session -> login form first (no guest mode)
  if(await welcome())rpc('vocab_event',{p_token:TOK,p_kind:'session_start'}).catch(()=>{});
}
function login(msg){
  shell(hero('เข้าสู่ระบบ')+`<div class="card"><form id="f" autocomplete="on">
  <label>เลขประจำตัวนักเรียน (5 หลัก)<input id="c" inputmode="numeric" pattern="[0-9]*" autocomplete="username" placeholder="เช่น 12345" maxlength="12" required></label>
  <label>เลขบัตรประชาชน (13 หลัก)<input id="p" type="password" inputmode="numeric" autocomplete="off" placeholder="เลขบัตรประชาชน 13 หลัก" maxlength="24" required></label>
  <div class="mut">ช่องที่ 1: เลขประจำตัวนักเรียน 5 หลัก · ช่องที่ 2: เลขบัตรประชาชน 13 หลัก (มีขีดหรือเว้นวรรคได้)</div>
  <div class="err" id="e">${esc(msg||'')}</div><button class="btn" id="go">เข้าสู่ระบบ</button></form></div>
  <div class="foot"><a href="privacy.html">ความเป็นส่วนตัว</a> · <a href="about.html">เกี่ยวกับ</a></div>`);
  $('#f').onsubmit=async ev=>{ev.preventDefault();const c=digits($('#c').value),p=digits($('#p').value);$('#e').textContent='';
    if(!/^[0-9]{5}$/.test(c))return $('#e').textContent='เลขประจำตัวนักเรียนต้องมี 5 หลัก';
    $('#go').disabled=true;
    try{const d=await rpc('vocab_login',{p_code:c,p_password:p});$('#p').value='';TOK=d.token;LS.set('kv2_tok',TOK);welcome()}
    catch(e){$('#e').textContent=e.code==='LOCKED'&&e.data?`ใส่เลขบัตรผิดหลายครั้ง รอประมาณ ${Math.max(1,Math.ceil(e.data.wait_s/60))} นาทีแล้วลองใหม่`:e.message;setTimeout(()=>{const g=$('#go');if(g)g.disabled=false},1500)}};
}
async function welcome(){
  if(!TOK){login();return false}
  try{ME=await rpc('vocab_me',{p_token:TOK})}catch(e){ME=null;if(e.code!=='NETWORK')dropSession();login(e.message);return false}
  if(!ME||ME.must_change){dropSession();login();return false}
  LS.set('kv2_me',ME);
  const ip=LS.get('kv2_ip',null);if(ip&&ip.tok===TOK&&ip.date===today()&&LV[ip.n]){play(ip);return true}
  const max=ME.max_level,cur=Math.min(ME.level,max),done=(ME.done_today||[]).includes(cur),fin=ME.level>max;
  shell(hero()+`<div class="card q" id="wel"><div style="font-size:56px">🎃</div><h2 id="wh">ยินดีต้อนรับเข้าสู่ระบบ</h2>
  <div class="big" id="wn" style="font-size:28px">${esc(ME.name)}</div><div class="mut">ม.${ME.grade}/${ME.room} · เลขที่ ${ME.no}</div>
  <div id="wl" style="font-size:20px;margin:12px 0">ตอนนี้คุณอยู่เลเวล ${cur}</div>
  ${fin?'<div class="mut">🎉 เล่นครบทุกด่านที่เปิดแล้ว!</div>':done?'<div class="mut">✅ วันนี้เล่นเลเวลนี้แล้ว มาเล่นใหม่พรุ่งนี้นะ</div>':`<button class="btn" id="ws">เริ่มทำแบบทดสอบ</button>`}
  <button class="btn sec" id="wm">🗺️ ไปหน้าแผนที่ด่าน</button><button class="btn sec" id="wd">📊 ข้อมูลของฉัน</button></div>`);
  if($('#ws'))$('#ws').onclick=()=>startLevel(cur);
  $('#wm').onclick=home;$('#wd').onclick=myDash;
  return true;
}
const bkk=(iso,o)=>iso?new Date(iso).toLocaleString('th-TH',Object.assign({timeZone:'Asia/Bangkok'},o||{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})):'-';
const peakTxt=d=>d.peak_date?`${new Date(d.peak_date+'T12:00:00+07:00').toLocaleDateString('th-TH',{timeZone:'Asia/Bangkok',weekday:'short',day:'numeric',month:'short'})} ช่วง ${String(d.peak_hour).padStart(2,'0')}:00–${String(d.peak_hour+1).padStart(2,'0')}:00 น. (${d.peak_n} ครั้ง)`:'ยังไม่เคยเล่น';
async function myDash(){
  let d;try{d=await rpc('vocab_my_dash',{p_token:TOK})}catch(e){if(e.code==='NO_SESSION'){dropSession();return login(e.message)}return alert(e.message)}
  const cur=Math.min(d.level,d.max_level);
  shell(`<div class="card" id="md"><h2>📊 ข้อมูลของฉัน</h2><div class="big" style="font-size:22px">${esc(d.name)}</div><div class="mut">ม.${d.g}/${d.r} · เลขที่ ${d.no} · เวลาไทย</div>
  <div class="dgrid"><div><b id="mdl">${cur}</b><span>เลเวลปัจจุบัน</span></div><div><b>${d.stars}</b><span>⭐ ดาวรวม</span></div><div><b>${d.points}</b><span>🏆 แต้ม</span></div><div><b id="mda">${d.attempts}</b><span>ครั้งที่เล่น</span></div></div>
  <div class="mut" style="margin:8px 0">เล่นล่าสุด: <b>${esc(bkk(d.last_at))}</b><br>ช่วงที่เล่นมากที่สุด: <b id="mdp">${esc(peakTxt(d))}</b></div>
  <h3>ประวัติการเล่น</h3><div style="max-height:46vh;overflow:auto"><table class="ht"><tr><th>เมื่อ</th><th>ด่าน</th><th>คะแนน</th><th>ดาว</th></tr>
  ${d.history.map(h=>`<tr><td>${esc(bkk(h.at))}</td><td>${h.l}</td><td>${h.s}/${h.q}</td><td>${starsTxt(h.st)}</td></tr>`).join('')||'<tr><td colspan="4" class="mut">ยังไม่เคยเล่น</td></tr>'}</table></div>
  <div class="mut" style="font-size:12px;margin-top:6px">แสดงเฉพาะข้อมูลของคุณเอง</div>
  <button class="btn" id="mdb">⬅ กลับ</button></div>`);
  $('#mdb').onclick=welcome;
}
function startLevel(n){if(!TOK||!ME)return login();CUR={tok:TOK,n,date:today(),qs:buildLevel(n),i:0,res:[],started:new Date().toISOString(),cid:n+'-'+Date.now()+'-'+Math.random().toString(36).slice(2,8)};LS.set('kv2_ip',CUR);play(CUR)}
function logout(){const t=TOK;if(t)rpc('vocab_event',{p_token:t,p_kind:'session_end'}).catch(()=>{}).then(()=>rpc('vocab_logout',{p_token:t})).catch(()=>{});dropSession();login()}
function best(n){const r=(ME.levels||[]).find(x=>x[0]===n);return r?{stars:r[1],score:r[2]}:null}
function home(){
  if(!TOK||!ME)return login();
  LS.set('kv2_me',ME);
  const ip=LS.get('kv2_ip',null);if(ip&&ip.tok===TOK&&ip.date===today()&&LV[ip.n])return play(ip);
  const done=ME.done_today||[],max=ME.max_level,cur=Math.min(ME.level,max);
  const pend=LS.get('kv2_q',[]).length;
  let nodes='';for(let n=1;n<=Math.min(V.levels.length,Math.max(max+3,8));n++){const l=LV[n];if(!l)break;const b=best(n),soon=n>max,lock=soon||n>ME.level,dt=done.includes(n);
    nodes+=`<button class="node ${n===cur&&!dt&&!lock?'cur':''} ${lock?'lock':''} ${b&&b.stars?'done':''}" data-n="${n}"><div class="ic">${soon?'🔒':l.icon}</div><div class="n">${n}</div><div class="st">${soon?'เร็ว ๆ นี้':lock?'🔒':starsTxt(b?b.stars:0)}</div></button>`}
  const l=LV[cur],can=!done.includes(cur)&&cur<=ME.level;
  shell(`<div class="top"><div class="pump" style="font-size:40px">🎃</div><div class="grow"><b>${esc(ME.name)}</b><div class="mut">ม.${ME.grade}/${ME.room} · เลขที่ ${ME.no} · ${esc(ME.code)}</div></div><span class="pill">⭐ ${ME.stars}</span> <span class="pill" id="pts">🏆 ${ME.points||0} แต้ม</span></div>
  <div class="card"><div class="mut">ด่านวันนี้ · Level ${cur} · ${l.band}</div><h2>${l.icon} คำศัพท์วันนี้: หมวด${esc(l.title)}</h2>
  <div class="mut">15 ข้อ · ผ่าน 9 ข้อขึ้นไป · ⭐ 9–10 · ⭐⭐ 11 · ⭐⭐⭐ 12–15 · เล่นได้ 1 ครั้ง/ด่าน/วัน</div>
  ${can?'<button class="btn" id="go">▶ เริ่มเล่นด่าน '+cur+'</button>':`<div class="card" style="background:var(--card2)">${ME.level>max?'🎉 เล่นครบทุกด่านที่เปิดแล้ว! เก่งมาก':'✅ วันนี้เล่นด่านนี้แล้ว มาเล่นใหม่พรุ่งนี้นะ'}</div>`}
  ${pend?`<div class="mut">⏳ มีผล ${pend} ด่านรอส่ง (จะส่งอัตโนมัติเมื่อมีเน็ต)</div>`:''}</div>
  <h2>🗺️ แผนที่ด่าน</h2><div class="map">${nodes}</div>
  <div class="mut" style="margin-top:8px">ผ่านด่าน (9/15 ขึ้นไป) แล้วเล่นด่านถัดไปได้ทันที · แต่ละด่านเล่นได้วันละ 1 ครั้ง · เล่นซ้ำวันอื่นเพื่อเก็บดาวและแต้มเพิ่ม</div>
  <button class="btn sec" id="lo">ออกจากระบบ</button><div class="foot"><a href="privacy.html">ความเป็นส่วนตัว</a> · <a href="about.html">เกี่ยวกับ</a></div>`);
  if(can)$('#go').onclick=()=>intro(cur);
  $('#lo').onclick=logout;
  app().querySelectorAll('.node').forEach(b=>b.onclick=()=>{const n=+b.dataset.n;if(n>max)return alert('ด่านนี้เร็ว ๆ นี้ 🎃');if(n>ME.level)return alert('ผ่านด่านก่อนหน้าก่อนนะ');if(done.includes(n))return alert(ERR.ALREADY_TODAY);intro(n)});
}
let CUR=null;
function intro(n){if(!TOK||!ME)return login();const l=LV[n];
  shell(`<div class="card q"><div class="mut">Level ${n} · ${l.band}</div><div style="font-size:64px">${l.icon}</div><h2>คำศัพท์วันนี้: หมวด${esc(l.title)}</h2>
  <div class="mut">15 ข้อ · ตอบแล้วย้อนกลับไม่ได้ · กด 🔊 ฟังเสียงได้<br>ด่านนี้เล่นได้ 1 ครั้งต่อวัน ตั้งใจนะ!</div>
  <button class="btn" id="go">เริ่มเลย 👻</button><button class="btn sec" id="bk">← กลับ</button></div>`);
  $('#bk').onclick=home;$('#go').onclick=()=>startLevel(n);
}
function play(s){if(!TOK||!s||s.tok!==TOK)return login();CUR=s;if(s.i>=s.qs.length)return finish();
  const q=s.qs[s.i],x=W[q.w],t0=Date.now(),one=q.t==='cloze'||q.t==='th';
  let head='';
  if(q.t==='pic')head=`<img class="qimg" src="${img(q.w)}" alt=""><div class="mut" style="margin-top:8px">ภาพนี้คือคำว่าอะไร?</div>`;
  if(q.t==='listen')head=`<button class="spk" id="sp">🔊</button><div class="mut" style="margin-top:8px">ฟังแล้วเลือกภาพที่ถูก</div>`;
  if(q.t==='th')head=`<div style="font-size:54px">${x.emo||'📘'}</div><div class="th">${esc(x.th)}</div><div class="mut">ตรงกับคำภาษาอังกฤษคำไหน?</div>`;
  if(q.t==='cloze')head=`<div style="font-size:44px">${x.emo||'📘'}</div><div style="font-size:19px">${esc(x.cl)}</div><div class="mut">เติมคำให้ถูก</div>`;
  const opts=q.o.map(o=>q.t==='listen'?`<button class="opt" data-o="${esc(o)}"><img src="${img(o)}" alt=""></button>`:`<button class="opt" data-o="${esc(o)}">${esc(o)}</button>`).join('');
  shell(`<div class="top"><span class="pill">Level ${s.n}</span><div class="grow"><div class="bar"><i style="width:${s.i/15*100}%"></i></div></div><span class="pill">${s.i+1}/15</span></div>
  <div class="card q">${head}${(x.t==='exam'||x.t==='both')?'<div><span class="tag">คำที่พบบ่อยในข้อสอบ</span></div>':''}<div class="opts ${one&&false?'one':''}">${opts}</div><div id="fb" style="min-height:52px;margin-top:10px"></div></div>`);
  if(q.t==='listen'){$('#sp').onclick=()=>say(q.w);setTimeout(()=>say(q.w),250)}
  let lock=false;
  app().querySelectorAll('.opt').forEach(b=>b.onclick=()=>{if(lock)return;lock=true;const a=b.dataset.o,ok=a===q.w;
    b.classList.add(ok?'ok':'bad');if(!ok)app().querySelector(`.opt[data-o="${CSS.escape(q.w)}"]`).classList.add('ok');
    say(q.w);$('#fb').innerHTML=`<div class="big" style="font-size:26px">${ok?'✅ เก่งมาก!':'❌ คำตอบคือ'} <b>${esc(q.w)}</b></div><div class="th">${esc(x.th)}</div>`;
    s.res.push({w:q.w,a,ms:Date.now()-t0,t:q.t});s.i++;LS.set('kv2_ip',s);
    const miss=LS.get('kv2_miss',[]).filter(m=>m!==q.w);if(!ok)miss.unshift(q.w);LS.set('kv2_miss',miss.slice(0,40));
    setTimeout(()=>play(s),ok?1100:1900)});
}
async function finish(){const s=CUR;
  const sc=s.res.filter(r=>r.w===r.a).length,st=sc>=12?3:sc===11?2:sc>=9?1:0;
  const job={tok:s.tok,n:s.n,res:s.res,started:s.started,cid:s.cid};
  {const q=LS.get('kv2_q',[]);if(!q.find(j=>j.cid===s.cid))q.push(job);LS.set('kv2_q',q);LS.del('kv2_ip');}
  shell(`<div class="card q"><div class="mut">Level ${s.n} · หมวด${esc(LV[s.n].title)}</div><h2>${st?'🎉 ผ่านด่าน!':'👻 ยังไม่ผ่าน'}</h2>
  <div class="big">${sc}/15</div><div class="stars" id="st"><span>★</span><span>★</span><span>★</span></div>
  <div class="mut">${st?'🔓 ปลดล็อกด่านถัดไปแล้ว!':'ต้องได้ 9 ข้อขึ้นไป · มาลองใหม่พรุ่งนี้นะ'}</div><div id="sv" class="mut">กำลังบันทึกผล…</div>
  <div style="text-align:left;margin-top:10px">${s.res.map(r=>`<div>${r.w===r.a?'✅':'❌'} <b>${esc(r.w)}</b> · ${esc(W[r.w].th)}${r.w===r.a?'':' <span class="mut">(ตอบ '+esc(r.a)+')</span>'}${(W[r.w].t==='exam'||W[r.w].t==='both')?' <span class="tag">ข้อสอบ</span>':''}</div>`).join('')}</div>
  <button class="btn" id="hm">กลับหน้าแผนที่</button></div>`);
  [0,1,2].forEach(i=>setTimeout(()=>{const e=app().querySelectorAll('#st span')[i];if(e&&i<st)e.classList.add('on')},500+i*450));
  $('#hm').onclick=async()=>{try{ME=await rpc('vocab_me',{p_token:TOK})}catch(e){if(e.code==='NO_SESSION'){dropSession();return login(e.message)}}home()};
  const ok=await flush(),rj=REJ[s.cid];$('#sv').textContent=rj?'⚠️ บันทึกผลไม่ได้: '+(ERR[rj]||rj):ok?'✅ บันทึกผลแล้ว':'⏳ ยังส่งผลไม่ได้ จะลองส่งใหม่อัตโนมัติ (อย่าลบข้อมูลเบราว์เซอร์)';
  try{ME=await rpc('vocab_me',{p_token:TOK})}catch(e){if(ME&&ME.done_today&&!ME.done_today.includes(s.n))ME.done_today.push(s.n)}
}
let flushing=false;const REJ={};
async function flush(){if(flushing)return false;flushing=true;let all=true;
  try{let q=LS.get('kv2_q',[]);for(const j of q.slice()){try{await rpc('vocab_submit',{p_token:j.tok,p_level:j.n,p_results:j.res,p_started_at:j.started,p_client_id:j.cid});q=q.filter(x=>x.cid!==j.cid)}
    catch(e){if(e.code==='NETWORK'||/^5|ERROR/.test(e.code))all=false;else{REJ[j.cid]=e.code;q=q.filter(x=>x.cid!==j.cid)}}LS.set('kv2_q',q)}}
  finally{flushing=false}return all}
window.addEventListener('online',flush);setInterval(flush,30000);
window.addEventListener('pagehide',()=>{if(TOK)try{fetch(VCFG.url+'/rest/v1/rpc/vocab_event',{method:'POST',keepalive:true,headers:{apikey:VCFG.key,'Content-Type':'application/json'},body:JSON.stringify({p_token:TOK,p_kind:'session_end'})})}catch(e){}});
window.__vocab={get CUR(){return CUR},W,LV};
start();
})();
