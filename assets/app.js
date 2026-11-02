(function(){
'use strict';
const V=window.VOCAB, W={}; V.words.forEach(w=>W[w.w]=w);
const STAGES=V.stages, MAXST=STAGES.length;
const STAGE_OF={}; STAGES.forEach(s=>s.words.forEach(w=>STAGE_OF[w]=s.n));
const CONF={}; V.conflicts.forEach(g=>g.forEach(a=>{CONF[a]=CONF[a]||new Set();g.forEach(b=>{if(a!==b)CONF[a].add(b)})}));
const BANDS=['A1','A2','B1','B2','C1','C2'];
const BAND_TH={A1:'เริ่มต้น',A2:'พื้นฐาน',B1:'กลาง',B2:'กลางสูง',C1:'สูง',C2:'เชี่ยวชาญ'};
const $=s=>document.querySelector(s), app=()=>$('#app');
const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const shuffle=a=>{a=a.slice();for(let i=a.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[a[i],a[j]]=[a[j],a[i]]}return a};
const LS={get(k,d){try{const v=localStorage.getItem('kv_'+k);return v==null?d:JSON.parse(v)}catch(e){return d}},set(k,v){localStorage.setItem('kv_'+k,JSON.stringify(v))},del(k){localStorage.removeItem('kv_'+k)}};
let S={token:LS.get('token',null),me:null,prog:{},tab:'home',size:LS.get('size',10)};
const SET=Object.assign({accent:'en-US',rate:0.9,sfx:true},LS.get('settings',{}));
function saveSet(){LS.set('settings',SET)}
function toast(m,ms){const t=document.createElement('div');t.className='toast';t.textContent=m;document.body.appendChild(t);setTimeout(()=>t.remove(),ms||2600)}
function imgSrc(w){return 'img/w/'+w.img+'.webp'}
function visual(w,cls){return w.img?`<img src="${imgSrc(w)}" alt="" ${cls||''} draggable="false">`:`<div class="emo">${w.emo||'📘'}</div>`}
function bandOf(stage){const s=STAGES[Math.min(stage,MAXST)-1];return stage>MAXST?'C2':s.band}
/* ---------- audio ---------- */
const TTS={ok:'speechSynthesis' in window,voice:null,
  pick(){if(!this.ok)return;const vs=speechSynthesis.getVoices();const want=SET.accent;
    this.voice=vs.find(v=>v.lang===want&&/Google|Samantha|Daniel|Natural|Premium|Enhanced/i.test(v.name))||vs.find(v=>v.lang===want)||vs.find(v=>v.lang&&v.lang.replace('_','-').startsWith(want))||vs.find(v=>/^en/i.test(v.lang))||null},
  say(text,slow){if(!this.ok)return false;try{speechSynthesis.cancel();if(!this.voice)this.pick();const u=new SpeechSynthesisUtterance(text);u.lang=SET.accent;if(this.voice)u.voice=this.voice;u.rate=slow?0.55:SET.rate;u.pitch=1.05;speechSynthesis.speak(u);return true}catch(e){return false}}};
if(TTS.ok){TTS.pick();speechSynthesis.onvoiceschanged=()=>TTS.pick()}
let AC=null;function beep(kind){if(!SET.sfx)return;try{AC=AC||new (window.AudioContext||window.webkitAudioContext)();const t=AC.currentTime;const seq=kind==='ok'?[[660,0],[880,.09]]:kind==='bad'?[[220,0],[180,.12]]:kind==='win'?[[523,0],[659,.1],[784,.2],[1047,.3]]:[[440,0]];
  seq.forEach(([f,d])=>{const o=AC.createOscillator(),g=AC.createGain();o.type=kind==='bad'?'sawtooth':'triangle';o.frequency.value=f;g.gain.setValueAtTime(.0001,t+d);g.gain.exponentialRampToValueAtTime(kind==='bad'?.08:.18,t+d+.02);g.gain.exponentialRampToValueAtTime(.0001,t+d+.18);o.connect(g);g.connect(AC.destination);o.start(t+d);o.stop(t+d+.2)})}catch(e){}}
function confetti(){const c=document.createElement('div');c.className='confetti';const cols=['#B40C3C','#F7A440','#2FA36B','#4A90D9','#8A5CD6','#FFD58A'];for(let i=0;i<70;i++){const p=document.createElement('i');p.style.left=Math.random()*100+'%';p.style.background=cols[i%cols.length];p.style.animationDelay=(Math.random()*.8)+'s';p.style.animationDuration=(2+Math.random()*1.5)+'s';c.appendChild(p)}document.body.appendChild(c);setTimeout(()=>c.remove(),4200)}
/* ---------- state ---------- */
function applyState(d){S.me=d.student;S.prog={};(d.progress||[]).forEach(([w,box,c,wr,seen])=>S.prog[w]={box,c,wr,seen});}
function box(w){return (S.prog[w]&&S.prog[w].box)||0}
function mastered(w){return box(w)>=2}
function masteredCount(){return Object.keys(S.prog).filter(mastered).length}
function stageInfo(n){const s=STAGES[Math.min(n,MAXST)-1];const m=s.words.filter(mastered).length;return {s,m,total:s.words.length}}
function petStage(){const m=masteredCount();return m<20?'egg':m<120?'chick':'egret'}
const PET_TH={egg:'ไข่นกยางน้อย',chick:'ลูกนกยาง',egret:'ราชานกยาง'};
/* ---------- question building ---------- */
const DUE=[0,0,1,3,7,14];
function isDue(w){const p=S.prog[w];if(!p||p.box<2)return false;return (Date.now()/1000-p.seen)>DUE[p.box]*86400}
function newPool(){const out=[];for(let n=S.me.stage;n<=MAXST&&out.length<40;n++)STAGES[n-1].words.forEach(w=>{if(!mastered(w))out.push(w)});return out}
function buildSession(N){
  const due=shuffle(Object.keys(S.prog).filter(isDue)).filter(w=>W[w]);
  const fresh=newPool();
  let nRev=Math.min(due.length,Math.floor(N*0.3));
  let pick=fresh.slice(0,N-nRev);
  if(pick.length<N-nRev)nRev=Math.min(due.length,N-pick.length);
  pick=pick.concat(due.slice(0,nRev));
  if(pick.length<N){const weak=shuffle(Object.keys(S.prog).filter(w=>W[w]&&!pick.includes(w)));pick=pick.concat(weak.slice(0,N-pick.length))}
  return shuffle(pick).slice(0,N);
}
function knownPool(min){let p=Object.keys(S.prog).filter(w=>W[w]);STAGES[Math.min(S.me.stage,MAXST)-1].words.forEach(w=>{if(!p.includes(w))p.push(w)});
  for(let n=S.me.stage-1;p.length<min&&n>=1;n--)STAGES[n-1].words.forEach(w=>{if(!p.includes(w))p.push(w)});
  for(let n=S.me.stage+1;p.length<min&&n<=MAXST;n++)STAGES[n-1].words.forEach(w=>{if(!p.includes(w))p.push(w)});return p}
function distractors(word,k,needImg){const t=W[word];const bad=CONF[word]||new Set();
  const ok=x=>x.w!==word&&!bad.has(x.w)&&(needImg?!!x.img:true)&&(!!x.img===!!t.img||needImg);
  let c=V.words.filter(x=>ok(x)&&x.lv===t.lv&&x.p===t.p);
  if(t.img&&t.p==='n'){const same=c.filter(x=>x.g===t.g);c=shuffle(same).slice(0,2).concat(shuffle(c.filter(x=>x.g!==t.g)))}else c=shuffle(c);
  if(c.length<k)c=c.concat(shuffle(V.words.filter(x=>ok(x)&&x.p===t.p&&!c.includes(x))));
  if(c.length<k)c=c.concat(shuffle(V.words.filter(x=>ok(x)&&!c.includes(x))));
  const out=[];const seen=new Set();for(const x of c){if(seen.has(x.w))continue;seen.add(x.w);out.push(x.w);if(out.length>=k)break}return out}
/* ---------- API wrappers ---------- */
async function call(fn,args){try{return await API.rpc(fn,args)}catch(e){if(e.code==='SESSION_EXPIRED'){logoutLocal();toast(e.message);throw e}throw e}}
function logoutLocal(){S.token=null;S.me=null;LS.del('token');renderAuth()}
async function flushPending(){const q=LS.get('pending',[]);if(!q.length||!S.token)return;const keep=[];for(const it of q){try{const d=await API.rpc('vocab_submit',{p_token:S.token,p_mode:it.mode,p_results:it.results});applyState(d)}catch(e){if(e.code==='NETWORK')keep.push(it)}}LS.set('pending',keep)}
/* ---------- AUTH ---------- */
function renderAuth(mode){mode=mode||'login';document.body.classList.remove('ingame');
  app().innerHTML=`<div class="hero"><img class="logo" src="assets/logo.png" alt="โลโก้"><h1>ศัพท์สนุก <span class="en">Word Quest</span></h1><p>โรงเรียนปิยมิตรวิทยา ฝ่ายมัธยม</p><img class="mascot" src="img/ui/pet_egret.webp" alt="มาสคอตนกยาง"></div>
  <div class="card"><div class="tabs"><button data-m="login" class="${mode==='login'?'on':''}">เข้าสู่ระบบ</button><button data-m="reg" class="${mode==='reg'?'on':''}">สมัครใหม่</button></div>
  <form id="authf" autocomplete="on">${mode==='reg'?`
   <label>รหัสห้องเรียน <span class="hint">(ขอจากครู เช่น PMV-ABCDE)</span></label><input name="cls" required autocapitalize="characters" placeholder="PMV-XXXXX">
   <label>ชื่อเล่นที่จะแสดงในเกม</label><input name="dn" required maxlength="30" placeholder="เช่น น้องมิว">
   <label>เลขที่ <span class="hint">(ไม่บังคับ)</span></label><input name="no" type="number" inputmode="numeric" min="1" max="99" placeholder="เช่น 12">`:''}
   <label>ชื่อผู้ใช้ <span class="hint">(a-z, 0-9, _ .)</span></label><input name="u" required autocapitalize="none" autocomplete="username" placeholder="เช่น mew_m12" spellcheck="false">
   <label>รหัสผ่าน</label><input name="p" type="password" required autocomplete="${mode==='reg'?'new-password':'current-password'}" placeholder="อย่างน้อย 4 ตัว">
   ${mode==='reg'?`<div class="check"><input type="checkbox" name="ok" id="pdpa"><label for="pdpa" style="margin:0;font-weight:400">ฉันอ่าน<a href="privacy.html" target="_blank">ประกาศความเป็นส่วนตัว</a>แล้ว และผู้ปกครองรับทราบ ระบบเก็บเฉพาะชื่อเล่น ห้อง เลขที่ และผลการเล่น</label></div>`:''}
   <div id="aerr" class="err hidden"></div><div style="height:16px"></div>
   <button class="btn" type="submit">${mode==='reg'?'เริ่มผจญภัย 🚀':'เข้าเล่น ▶'}</button></form></div>
  <div class="foot"><a href="privacy.html">ความเป็นส่วนตัว</a> · <a href="about.html">เกี่ยวกับ / แหล่งคำศัพท์</a> · <a href="teacher.html">สำหรับครู</a></div>`;
  app().querySelectorAll('.tabs button').forEach(b=>b.onclick=()=>renderAuth(b.dataset.m));
  $('#authf').onsubmit=async e=>{e.preventDefault();const f=e.target,er=$('#aerr');er.classList.add('hidden');const btn=f.querySelector('button[type=submit]');
    if(mode==='reg'&&!f.ok.checked){er.textContent='กรุณาติ๊กยอมรับประกาศความเป็นส่วนตัวก่อนนะ';er.classList.remove('hidden');return}
    btn.disabled=true;try{const d=mode==='reg'?await API.rpc('vocab_register',{p_class_code:f.cls.value.trim(),p_username:f.u.value.trim(),p_password:f.p.value,p_display_name:f.dn.value.trim(),p_student_no:f.no.value?parseInt(f.no.value,10):null}):await API.rpc('vocab_login',{p_username:f.u.value.trim(),p_password:f.p.value});
      S.token=d.token;LS.set('token',d.token);applyState(d);if(mode==='reg')LS.set('intro',0);S.tab='home';renderMain();window.scrollTo(0,0)}
    catch(x){er.textContent=x.message;er.classList.remove('hidden')}finally{btn.disabled=false}};
}
/* ---------- MAIN ---------- */
function topbar(){const m=S.me;return `<div class="top"><div class="avatar"><img src="img/ui/pet_${petStage()}.webp" alt=""></div><div class="grow"><div style="font-weight:600;line-height:1.1">${esc(m.display_name)}</div><div class="muted" style="font-size:13px">${esc(m.class_name)}${m.student_no?' · เลขที่ '+m.student_no:''}</div></div>
  <span class="pill" title="วันต่อเนื่อง">🔥 ${m.streak}</span><span class="pill" title="XP">⭐ ${m.xp}</span></div>`}
function nav(){const t=[['home','🏠','หน้าหลัก'],['map','🗺️','แผนที่'],['album','📚','คลังคำ'],['board','🏆','อันดับ'],['me','🙂','ฉัน']];
  return `<nav class="nav"><div>${t.map(([k,i,l])=>`<button data-t="${k}" class="${S.tab===k?'on':''}"><span class="i">${i}</span>${l}</button>`).join('')}</div></nav>`}
function renderMain(){document.body.classList.remove('ingame');const v={home:viewHome,map:viewMap,album:viewAlbum,board:viewBoard,me:viewMe}[S.tab]||viewHome;
  app().innerHTML=topbar()+'<div id="view"></div>'+nav();app().querySelectorAll('.nav button').forEach(b=>b.onclick=()=>{S.tab=b.dataset.t;renderMain();window.scrollTo(0,0)});v($('#view'))}
const MODES=[['match','🧩','จับคู่ภาพ','แตะจับคู่ภาพกับคำ'],['listen','🎧','ฟังแล้วเลือก','ฟังเสียงแล้วแตะภาพ'],['say','🎤','ฝึกออกเสียง','ฟัง แล้วพูดตาม'],['rush','⚡','ไทม์รัช 60 วิ','ตอบให้ได้มากที่สุด'],['boss','👾','บอสบึงกว๊าน','ตอบถูกเพื่อโจมตีบอส'],['review','🔁','ทบทวนคำยาก','คำที่เคยตอบผิด']];
function viewHome(el){const m=S.me;const st=Math.min(m.stage,MAXST);const si=stageInfo(st);const band=bandOf(m.stage);const done=m.today_sessions>0;
  const today=new Date().toLocaleDateString('th-TH',{weekday:'long',day:'numeric',month:'long'});
  const intro=LS.get('intro',1)?'':`<div class="card" style="background:#E6F0FB"><b>👋 ยินดีต้อนรับ!</b><div style="font-size:15px;margin-top:4px">ทุกเช้าเล่น “ภารกิจเช้านี้” 10–20 คำ ดูภาพแล้วเลือกคำให้ถูก ตอบถูก 2 รอบ (คนละรอบเล่น) = จำได้แล้ว จำครบทุกคำในด่าน = ผ่านด่าน! เริ่มจาก A1 แล้วไต่ขึ้นไปถึง C2 ตามจังหวะของตัวเอง</div><button class="btn sm sky" id="introok" style="margin-top:10px">เข้าใจแล้ว</button></div>`;
  el.innerHTML=intro+`<div class="card quest"><div class="sun"></div><div class="muted" style="font-size:14px">${today}</div><h2>☀️ ภารกิจเช้านี้</h2>
   <div class="row" style="margin-top:8px"><span class="band b${band}">${band}</span><span style="font-weight:600">ด่าน ${st} · ${esc(si.s.title)}</span></div>
   <div class="row" style="margin-top:8px"><div class="bar grow"><i style="width:${Math.round(si.m/si.total*100)}%"></i></div><span class="muted" style="font-size:14px">${si.m}/${si.total}</span></div>
   <div class="sizes">${[10,15,20].map(n=>`<button data-n="${n}" class="${S.size===n?'on':''}">${n} คำ</button>`).join('')}</div>
   <button class="btn" id="go">${done?'เล่นอีกรอบ ▶':'เริ่มภารกิจ ▶'}</button>${done?'<div class="center muted" style="font-size:14px;margin-top:10px">✅ วันนี้ทำภารกิจแล้ว เก่งมาก!</div>':''}</div>
   <div class="modes"><button class="mode main" data-mode="pick"><img src="img/w/${(W[si.s.words[0]]&&W[si.s.words[0]].img)||'apple'}.webp" alt=""><div><b>ทายภาพ → คำ</b><br><span>โหมดหลัก ดูภาพแล้วเลือกคำศัพท์ที่ถูก พร้อมเสียงอ่าน</span></div></button>
   ${MODES.map(([k,i,t,d])=>`<button class="mode" data-mode="${k}"><span class="ic">${i}</span><b>${t}</b><span>${d}</span></button>`).join('')}</div>
   <div class="card petcard"><img src="img/ui/pet_${petStage()}.webp" alt=""><div><b>${PET_TH[petStage()]}</b><div class="muted" style="font-size:14px">จำได้แล้ว ${masteredCount()} คำ · ${petStage()==='egg'?'จำครบ 20 คำ ไข่จะฟัก!':petStage()==='chick'?'จำครบ 120 คำ จะโตเป็นราชานกยาง':'สุดยอด! เลี้ยงนกยางให้เก่งต่อไป'}</div><div class="muted" style="font-size:14px">สถิติวันต่อเนื่องสูงสุด 🔥 ${m.best_streak} วัน</div></div></div>`;
  const io=$('#introok');if(io)io.onclick=()=>{LS.set('intro',1);renderMain()};
  el.querySelectorAll('.sizes button').forEach(b=>b.onclick=()=>{S.size=+b.dataset.n;LS.set('size',S.size);viewHome(el)});
  $('#go').onclick=()=>startGame('pick');
  el.querySelectorAll('.mode').forEach(b=>b.onclick=()=>startGame(b.dataset.mode));}
function viewMap(el){const cur=S.me.stage;let html='',lastBand=null;
  STAGES.forEach((s,i)=>{const cls=s.n<cur?'done':s.n===cur?'cur':'';const off=Math.round(Math.sin(i*0.9)*70);
    html+=`<div class="node ${cls}" style="transform:translateX(${off}px)" id="nd${s.n}">${s.n<cur?'★':s.n}<small>${esc(s.title)}</small></div>`;
    const nb=STAGES[i+1]?STAGES[i+1].band:null;if(nb!==s.band)html+=`<div class="bandlabel"><span class="band b${s.band}">${s.band}</span> ${BAND_TH[s.band]} ${cur>s.n?'✓':''}</div>`});
  el.innerHTML=`<div class="card" style="margin-bottom:0"><b>🗺️ เส้นทางผจญภัย A1 → C2</b><div class="muted" style="font-size:14px">${MAXST} ด่าน · ตอนนี้อยู่ด่าน ${Math.min(cur,MAXST)} (${bandOf(cur)} ${BAND_TH[bandOf(cur)]})</div></div><div class="map"><div class="path">${html}</div></div>`;
  const n=$('#nd'+Math.min(cur,MAXST));if(n)setTimeout(()=>n.scrollIntoView({block:'center'}),50)}
function viewAlbum(el,band){band=band||bandOf(S.me.stage);const ws=V.words.filter(w=>STAGES[STAGE_OF[w.w]-1].band===band);const got=ws.filter(w=>mastered(w.w)).length;
  el.innerHTML=`<div class="card"><b>📚 คลังคำของฉัน</b><div class="muted" style="font-size:14px">แตะคำเพื่อฟังเสียง · สะสมแล้ว ${masteredCount()} / ${V.words.length} คำ</div><div class="seg" style="margin-top:10px">${BANDS.map(b=>`<button data-b="${b}" class="${b===band?'on':''}">${b}</button>`).join('')}</div><div class="muted" style="font-size:14px;margin-top:8px">${band}: ${got}/${ws.length}</div></div>
  <div class="album">${ws.map(w=>`<button class="aw ${mastered(w.w)?'':'lock'}" data-w="${esc(w.w)}">${visual(w,'loading="lazy"')}<b>${esc(w.w)}</b><small>${esc(w.th)}</small></button>`).join('')}</div>`;
  el.querySelectorAll('.seg button').forEach(b=>b.onclick=()=>viewAlbum(el,b.dataset.b));el.querySelectorAll('.aw').forEach(b=>b.onclick=()=>TTS.say(b.dataset.w))}
async function viewBoard(el){el.innerHTML='<div class="card center muted">กำลังโหลด…</div>';try{const rows=await call('vocab_leaderboard',{p_token:S.token});
  el.innerHTML=`<div class="card"><b>🏆 อันดับในห้อง ${esc(S.me.class_name)}</b><div class="muted" style="font-size:13px">แสดงเฉพาะชื่อเล่น XP และด่าน · แข่งกับตัวเองเมื่อวานก็เท่ไม่แพ้กัน!</div><div style="margin-top:8px">${rows.map((r,i)=>`<div class="lb ${r.me?'me':''}"><span class="n">${i<3?['🥇','🥈','🥉'][i]:i+1}</span><span class="grow">${esc(r.name)}</span><span class="band b${r.band}">${r.band}</span><span class="pill">⭐ ${r.xp}</span></div>`).join('')||'<div class="muted">ยังไม่มีข้อมูล</div>'}</div></div>`}catch(e){el.innerHTML=`<div class="card err">${esc(e.message)}</div>`}}
let deferredPrompt=null;window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();deferredPrompt=e});
function viewMe(el){const m=S.me;const acc=m.answered?Math.round(m.correct/m.answered*100):0;
  el.innerHTML=`<div class="card"><b>🙂 ข้อมูลของฉัน</b><div class="stats"><div class="stat"><b>${bandOf(m.stage)}</b><span>ระดับ CEFR</span></div><div class="stat"><b>${masteredCount()}</b><span>คำที่จำได้</span></div><div class="stat"><b>${acc}%</b><span>ตอบถูก</span></div></div>
  <div class="muted" style="font-size:14px">ชื่อผู้ใช้: ${esc(m.username)} · เล่นแล้ว ${m.sessions} รอบ</div></div>
  <div class="card"><b>🔊 เสียงอ่าน</b><div class="seg" style="margin-top:8px"><button data-a="en-US" class="${SET.accent==='en-US'?'on':''}">🇺🇸 อเมริกัน</button><button data-a="en-GB" class="${SET.accent==='en-GB'?'on':''}">🇬🇧 อังกฤษ</button></div>
  <div class="seg" style="margin-top:8px"><button data-r="0.75" class="${SET.rate==0.75?'on':''}">ช้า</button><button data-r="0.9" class="${SET.rate==0.9?'on':''}">ปกติ</button><button data-r="1" class="${SET.rate==1?'on':''}">เร็ว</button><button id="sfx" class="${SET.sfx?'on':''}">เสียงเอฟเฟกต์ ${SET.sfx?'เปิด':'ปิด'}</button></div>
  <button class="btn ghost sm" id="test" style="margin-top:10px">ทดลองฟัง “Good morning!”</button>${TTS.ok?'':'<div class="err">อุปกรณ์นี้ไม่รองรับเสียงอ่าน ลองเปิดด้วย Chrome หรือ Safari รุ่นใหม่</div>'}</div>
  <div class="card"><button class="btn gold" id="inst">📲 ติดตั้งแอปบนหน้าจอ</button><div class="muted" style="font-size:13px;margin-top:8px">iPhone: กดปุ่มแชร์ใน Safari → “เพิ่มไปยังหน้าจอโฮม”</div></div>
  <div class="card"><button class="btn ghost" id="out">ออกจากระบบ</button><div style="height:12px"></div><button class="btn ghost" id="del" style="color:var(--bad-d)">ลบบัญชีและข้อมูลของฉัน</button></div>
  <div class="foot"><a href="privacy.html">ความเป็นส่วนตัว</a> · <a href="about.html">เกี่ยวกับ / แหล่งคำศัพท์</a> · v${VCFG.version}</div>`;
  el.querySelectorAll('[data-a]').forEach(b=>b.onclick=()=>{SET.accent=b.dataset.a;saveSet();TTS.voice=null;TTS.pick();viewMe(el);TTS.say('Good morning!')});
  el.querySelectorAll('[data-r]').forEach(b=>b.onclick=()=>{SET.rate=+b.dataset.r;saveSet();viewMe(el)});
  $('#sfx').onclick=()=>{SET.sfx=!SET.sfx;saveSet();viewMe(el)};$('#test').onclick=()=>TTS.say('Good morning!');
  $('#inst').onclick=async()=>{if(deferredPrompt){deferredPrompt.prompt();deferredPrompt=null}else toast('ใช้เมนูของเบราว์เซอร์ “เพิ่มไปยังหน้าจอหลัก”')};
  $('#out').onclick=async()=>{try{await API.rpc('vocab_logout',{p_token:S.token})}catch(e){}logoutLocal()};
  $('#del').onclick=async()=>{const p=prompt('ยืนยันลบบัญชีถาวร: พิมพ์รหัสผ่านของคุณ');if(!p)return;try{await call('vocab_delete_me',{p_token:S.token,p_password:p});toast('ลบบัญชีเรียบร้อย');logoutLocal()}catch(e){toast(e.message)}}}
/* ---------- GAME ENGINE ---------- */
let G=null;
function startGame(mode){if(!S.me)return;
  let words;
  if(mode==='pick')words=buildSession(S.size);
  else if(mode==='review'){words=Object.keys(S.prog).filter(w=>W[w]&&S.prog[w].wr>0).sort((a,b)=>(S.prog[b].wr-S.prog[b].c)-(S.prog[a].wr-S.prog[a].c)).slice(0,10);if(words.length<4){toast('ยังไม่มีคำที่ตอบผิด เล่นภารกิจก่อนนะ 👍');return}mode='pick';G={review:true}}
  else if(mode==='match')words=shuffle(knownPool(12)).slice(0,12);
  else if(mode==='listen')words=shuffle(knownPool(10)).slice(0,10);
  else if(mode==='say')words=shuffle(knownPool(8)).slice(0,8);
  else if(mode==='rush')words=shuffle(knownPool(40));
  else if(mode==='boss')words=shuffle(knownPool(14)).slice(0,14);
  G=Object.assign({mode,words,i:0,res:{},combo:0,best:0,queue:words.slice(),retry:[]},G&&G.review?{review:true}:{});
  document.body.classList.add('ingame');window.scrollTo(0,0);
  ({pick:playPick,match:playMatch,listen:playListen,say:playSay,rush:playRush,boss:playBoss})[mode]();}
function record(w,ok){if(!(w in G.res))G.res[w]=ok;if(ok){G.combo++;G.best=Math.max(G.best,G.combo)}else G.combo=0}
function head(extra){const total=G.words.length;const done=Object.keys(G.res).length;const pct=G.mode==='rush'?0:Math.round(done/total*100);
  return `<div class="ghead"><button class="x" id="quit" aria-label="ออก">✕</button><div class="bar green grow">${G.mode==='rush'?'<i id="tbar" style="width:100%"></i>':`<i style="width:${pct}%"></i>`}</div>${extra||`<span class="combo ${G.combo>=3?'hot':''}">${G.combo>=2?'🔥x'+G.combo:''}</span>`}</div>`}
function bindQuit(){$('#quit').onclick=()=>{if(Object.keys(G.res).length&&!confirm('ออกจากเกม? คำที่ตอบไปแล้วจะถูกบันทึก'))return;finish(true)}}
function feedback(ok,w,next){const f=document.createElement('div');f.className='feedback show '+(ok?'good':'wrong');const ww=W[w];
  f.innerHTML=`<div class="in"><h3>${ok?['เยี่ยมมาก! 🎉','ถูกต้อง! ✨','เก่งสุด ๆ! 🌟','ใช่เลย! 💯'][Math.floor(Math.random()*4)]:'ไม่เป็นไร ลองจำใหม่นะ 💪'}</h3><div class="row"><div class="grow"><span class="w">${esc(ww.w)}</span> <button class="pill" id="fbs">🔊</button><div>${esc(ww.th)}</div>${ww.ex&&!ok?`<div class="en" style="font-size:15px;margin-top:4px">${esc(ww.ex)}</div>`:''}</div></div><div style="height:12px"></div><button class="btn ${ok?'ok':''}" id="fbn">ไปต่อ ➜</button></div>`;
  document.body.appendChild(f);TTS.say(ww.w);$('#fbs').onclick=()=>TTS.say(ww.w);$('#fbn').onclick=()=>{f.remove();next()}}
function qPick(w,onDone,opts){opts=opts||{};G.cur=w;const t=W[w];const choices=shuffle([w].concat(distractors(w,3)));
  const body=t.img?`<div class="prompt">ภาพนี้คือคำว่าอะไร?</div><div class="pic">${visual(t)}<button class="speak" id="spk" aria-label="ฟังเสียง">🔊</button></div>`
   :`<div class="prompt">เลือกคำที่เติมในช่องว่างได้ <span class="hint">(ในประโยคอาจเปลี่ยนรูป เช่น -s, -ed)</span></div><div class="pic text"><div class="emo">${t.emo||'📘'}</div><div class="cloze">${esc(t.cl).replace('___','<u></u>')}</div><button class="pill" id="hintb">💡 ใบ้ความหมาย</button><div id="hintt" class="muted hidden">${esc(t.th)}</div></div>`;
  return {html:body+`<div class="opts">${choices.map(c=>`<button class="opt" data-c="${esc(c)}">${esc(c)}</button>`).join('')}</div>`,
   bind(){const sp=$('#spk');if(sp)sp.onclick=()=>TTS.say(w);const hb=$('#hintb');if(hb)hb.onclick=()=>$('#hintt').classList.remove('hidden');
    let locked=false;document.querySelectorAll('.opt').forEach(b=>b.onclick=()=>{if(locked)return;locked=true;const ok=b.dataset.c===w;
     document.querySelectorAll('.opt').forEach(o=>{if(o.dataset.c===w)o.classList.add('ok');else if(o===b)o.classList.add('bad');else o.classList.add('dim')});
     beep(ok?'ok':'bad');onDone(ok)})}}}
function playPick(){const w=G.queue.shift();if(!w){if(G.retry.length){G.queue=G.retry;G.retry=[];G.retryRound=true;return playPick()}return finish()}
  const q=qPick(w,ok=>{if(!G.retryRound)record(w,ok);else if(ok)G.combo++;if(!ok&&!G.retryRound)G.retry.push(w);setTimeout(()=>feedback(ok,w,playPick),350)});
  app().innerHTML=`<div class="game">${head()}${G.retryRound?'<div class="center muted" style="margin-top:6px">🔁 รอบแก้ตัว (ฝึกเพิ่ม)</div>':''}${q.html}</div>`;bindQuit();q.bind();if(W[w].img)setTimeout(()=>TTS.say(w),250)}
function playListen(){const w=G.queue.shift();if(!w)return finish();G.cur=w;const t=W[w];const choices=shuffle([w].concat(distractors(w,3,!!t.img)));
  app().innerHTML=`<div class="game">${head()}<div class="prompt center">ฟังแล้วแตะ${t.img?'ภาพ':'คำ'}ที่ได้ยิน</div><button class="listenbig" id="play">🔊</button><div class="center"><button class="pill" id="slow">🐢 ฟังช้า ๆ</button></div>
   <div class="opts">${choices.map(c=>t.img?`<button class="opt picopt" data-c="${esc(c)}">${visual(W[c])}</button>`:`<button class="opt" data-c="${esc(c)}">${esc(c)}</button>`).join('')}</div></div>`;
  bindQuit();$('#play').onclick=()=>TTS.say(w);$('#slow').onclick=()=>TTS.say(w,true);setTimeout(()=>TTS.say(w),300);
  let locked=false;document.querySelectorAll('.opt').forEach(b=>b.onclick=()=>{if(locked)return;locked=true;const ok=b.dataset.c===w;
   document.querySelectorAll('.opt').forEach(o=>{if(o.dataset.c===w)o.classList.add('ok');else if(o===b)o.classList.add('bad');else o.classList.add('dim')});beep(ok?'ok':'bad');record(w,ok);setTimeout(()=>feedback(ok,w,playListen),350)})}
function playMatch(){const round=G.queue.splice(0,4);if(round.length<2)return finish();
  const left=shuffle(round),right=shuffle(round);let sel=null,left_n=round.length;const miss=new Set();
  app().innerHTML=`<div class="game">${head()}<div class="prompt center">จับคู่${round.every(w=>W[w].img)?'ภาพ':'ภาพ/ความหมาย'}กับคำให้ถูก</div><div class="match"><div class="col">${left.map(w=>`<button class="mt ${W[w].img?'':'th'}" data-l="${esc(w)}">${W[w].img?visual(W[w]):esc((W[w].emo||'')+' '+W[w].th)}</button>`).join('')}</div><div class="col">${right.map(w=>`<button class="mt" data-r="${esc(w)}">${esc(w)}</button>`).join('')}</div></div></div>`;
  bindQuit();const pick=(b)=>{document.querySelectorAll('.mt.sel').forEach(x=>x.classList.remove('sel'));b.classList.add('sel');sel=b};
  document.querySelectorAll('.mt').forEach(b=>b.onclick=()=>{if(b.classList.contains('done'))return;
    if(!sel||(sel.dataset.l&&b.dataset.l)||(sel.dataset.r&&b.dataset.r)){pick(b);if(b.dataset.r)TTS.say(b.dataset.r);return}
    const a=sel.dataset.l||b.dataset.l, c=sel.dataset.r||b.dataset.r;
    if(a===c){[sel,b].forEach(x=>{x.classList.remove('sel');x.classList.add('ok','done')});record(a,!miss.has(a));beep('ok');TTS.say(a);sel=null;left_n--;if(!left_n)setTimeout(playMatch,600)}
    else{miss.add(a);G.combo=0;beep('bad');[sel,b].forEach(x=>{x.classList.add('bad');setTimeout(()=>x.classList.remove('bad','sel'),400)});sel=null}})}
const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
function lev(a,b){const m=a.length,n=b.length,d=[];for(let i=0;i<=m;i++){d[i]=[i]}for(let j=1;j<=n;j++)d[0][j]=j;for(let i=1;i<=m;i++)for(let j=1;j<=n;j++)d[i][j]=Math.min(d[i-1][j]+1,d[i][j-1]+1,d[i-1][j-1]+(a[i-1]===b[j-1]?0:1));return d[m][n]}
const norm=s=>s.toLowerCase().replace(/[^a-z ]/g,'').replace(/\s+/g,' ').trim();
function playSay(){const w=G.queue.shift();if(!w)return finish();G.cur=w;const t=W[w];let tries=0;
  app().innerHTML=`<div class="game">${head()}<div class="prompt center">ฟังเสียง แล้วลองพูดตาม</div><div class="pic" style="max-width:220px">${visual(t)}</div><div class="bigword">${esc(w)}</div><div class="thai">${esc(t.th)}</div>
   <div class="row" style="justify-content:center;margin-top:10px;gap:10px"><button class="btn sky sm" id="p1">🔊 ฟัง</button><button class="btn ghost sm" id="p2">🐢 ช้า</button></div>
   ${SR?`<button class="mic" id="mic">🎤</button><div class="center muted" id="said">แตะไมค์แล้วพูดคำนี้</div><div class="center" style="margin-top:8px"><button class="pill" id="skip">ข้ามคำนี้</button></div>`
   :`<div class="card center" style="margin:14px 0"><div class="muted" style="font-size:14px">เบราว์เซอร์นี้ยังไม่รองรับการฟังเสียงพูด ฝึกพูดตามดัง ๆ แล้วประเมินตัวเอง</div><div class="row" style="margin-top:10px"><button class="btn ok sm grow" id="selfok">✅ พูดได้แล้ว</button><button class="btn ghost sm grow" id="selfno">🔁 ยังไม่มั่นใจ</button></div></div>`}</div>`;
  bindQuit();$('#p1').onclick=()=>TTS.say(w);$('#p2').onclick=()=>TTS.say(w,true);setTimeout(()=>TTS.say(w),300);
  const done=ok=>{beep(ok?'ok':'bad');record(w,ok);setTimeout(()=>feedback(ok,w,playSay),300)};
  if(!SR){$('#selfok').onclick=()=>done(true);$('#selfno').onclick=()=>done(false);return}
  $('#skip').onclick=()=>done(false);
  $('#mic').onclick=()=>{const r=new SR();r.lang='en-US';r.maxAlternatives=5;r.interimResults=false;const mic=$('#mic');mic.classList.add('rec');$('#said').textContent='กำลังฟัง…';
    r.onresult=e=>{const alts=[...e.results[0]].map(a=>norm(a.transcript));const target=norm(w);const good=alts.some(a=>a===target||a.split(' ').includes(target)||(1-lev(a,target)/Math.max(target.length,1))>=0.75);
      tries++;if(good)done(true);else{$('#said').innerHTML=`ได้ยินว่า “<span class="en">${esc(alts[0]||'…')}</span>” ลองอีกครั้งนะ (${tries}/3)`;beep('bad');if(tries>=3)done(false)}};
    r.onerror=e=>{$('#said').textContent=e.error==='not-allowed'?'ไม่ได้รับอนุญาตใช้ไมค์ — กด “ข้าม” หรืออนุญาตไมค์ในการตั้งค่า':'ไม่ได้ยินเสียง ลองใหม่อีกครั้ง'};
    r.onend=()=>mic.classList.remove('rec');try{r.start()}catch(e){}}}
function playRush(){G.end=G.end||Date.now()+60000;G.score=G.score||0;
  const tick=()=>{const left=Math.max(0,G.end-Date.now());const tb=$('#tbar');if(tb)tb.style.width=(left/600)+'%';const tm=$('#tm');if(tm)tm.textContent=Math.ceil(left/1000)+'s';if(left<=0){clearInterval(G.timer);finish()}};
  if(!G.timer)G.timer=setInterval(tick,200);
  let w=G.queue.shift();if(!w){G.queue=shuffle(G.words);w=G.queue.shift()}
  const q=qPick(w,ok=>{record(w,ok);if(ok)G.score++;setTimeout(()=>{if(G&&G.mode==='rush'&&Date.now()<G.end)playRush()},ok?250:700)});
  app().innerHTML=`<div class="game">${head(`<span class="timer" id="tm">60s</span>`)}<div class="center" style="font-weight:600;margin-top:6px">⚡ ${G.score} คะแนน ${G.combo>=3?'🔥x'+G.combo:''}</div>${q.html}</div>`;bindQuit();q.bind();tick()}
function playBoss(){G.hp=G.hp==null?10:G.hp;G.sh=G.sh==null?3:G.sh;const w=G.queue.shift();if(!w||G.hp<=0||G.sh<=0)return finish();
  const q=qPick(w,ok=>{record(w,ok);const bx=$('.boss');if(ok){G.hp=Math.max(0,G.hp-(G.combo>=3?2:1));bx.classList.add('hit')}else G.sh--;
    $('#hpb').style.width=(G.hp*10)+'%';$('#shd').textContent='🛡️'.repeat(Math.max(G.sh,0))+'🖤'.repeat(3-Math.max(G.sh,0));
    setTimeout(()=>feedback(ok,w,playBoss),450)});
  app().innerHTML=`<div class="game">${head()}<div class="boss"><img src="img/ui/boss_kwan.webp" alt="บอส"><div class="grow"><b>บอสหมอกบึงกว๊าน</b><div class="hp"><i id="hpb" style="width:${G.hp*10}%"></i></div><div class="shields" id="shd">${'🛡️'.repeat(G.sh)+'🖤'.repeat(3-G.sh)}</div></div></div>${q.html}</div>`;bindQuit();q.bind()}
async function finish(quit){if(G.timer){clearInterval(G.timer);G.timer=null}document.querySelectorAll('.feedback').forEach(f=>f.remove());
  const results=Object.entries(G.res).map(([w,ok])=>({w,ok}));
  if(!results.length){G=null;renderMain();return}
  const mode=G.mode, n=results.length, ok=results.filter(r=>r.ok).length;
  app().innerHTML=`<div class="result"><div class="muted">กำลังบันทึกผล…</div></div>`;
  let r=null,offline=false;try{const d=await call('vocab_submit',{p_token:S.token,p_mode:mode,p_results:results.slice(0,60)});r=d.result;applyState(d)}
  catch(e){if(e.code==='SESSION_EXPIRED')return;offline=true;const q=LS.get('pending',[]);q.push({mode,results:results.slice(0,60)});LS.set('pending',q)}
  const won=mode==='boss'?G.hp<=0:null;const up=r&&r.stage_after>r.stage_before;const bandUp=r&&r.band_after!==r.band_before;
  const title=mode==='boss'?(won?'ชนะบอสแล้ว! 🏆':'บอสหนีไปก่อน ครั้งหน้าเอาใหม่!'):ok===n?'เพอร์เฟกต์! 🌟':ok/n>=.7?'เยี่ยมมาก! 🎉':'ฝึกต่อเรื่อย ๆ เก่งขึ้นแน่ 💪';
  const si=stageInfo(Math.min(S.me.stage,MAXST));
  app().innerHTML=`<div class="result"><img class="cel" src="img/ui/${up||won||ok===n?'celebrate':'pet_'+petStage()}.webp" alt=""><h2 style="margin:14px 0 0">${title}</h2>
   ${up?`<div class="levelup">${bandUp?`🎊 เลื่อนระดับเป็น ${r.band_after}!`:'🎊 ผ่านด่านแล้ว!'} ตอนนี้อยู่ด่าน ${Math.min(r.stage_after,MAXST)}</div>`:''}
   <div class="stats"><div class="stat"><b>${ok}/${n}</b><span>ตอบถูก</span></div><div class="stat"><b>+${r?r.xp:'—'}</b><span>XP</span></div><div class="stat"><b>🔥${G.best}</b><span>คอมโบสูงสุด</span></div></div>
   ${offline?'<div class="err">ยังบันทึกไม่ได้ (ออฟไลน์) ระบบจะส่งให้อัตโนมัติเมื่อกลับมาออนไลน์</div>':''}
   <div class="card" style="margin:12px 0;text-align:left"><b>ด่าน ${Math.min(S.me.stage,MAXST)} · ${esc(si.s.title)}</b><div class="row" style="margin-top:6px"><div class="bar grow"><i style="width:${Math.round(si.m/si.total*100)}%"></i></div><span class="muted">${si.m}/${si.total}</span></div><div class="muted" style="font-size:13px;margin-top:6px">คำจะถือว่า “จำได้” เมื่อตอบถูก 2 รอบเล่น (คนละรอบ)</div></div>
   <button class="btn" id="home">กลับหน้าหลัก</button><div style="height:12px"></div><button class="btn ghost" id="again">เล่นอีกครั้ง</button></div>`;
  if(up||won||ok===n){beep('win');confetti()}
  const m=G.review?'review':mode;G=null;$('#home').onclick=()=>{S.tab='home';renderMain();window.scrollTo(0,0)};$('#again').onclick=()=>startGame(m)}
/* ---------- boot ---------- */
async function boot(){if('serviceWorker' in navigator)navigator.serviceWorker.register('sw.js').catch(()=>{});
  if(!S.token)return renderAuth();
  app().innerHTML='<div class="hero"><img class="mascot" src="img/ui/pet_egret.webp" alt=""><p>กำลังโหลด…</p></div>';
  try{await flushPending();const d=await call('vocab_state',{p_token:S.token});applyState(d);renderMain()}
  catch(e){if(e.code!=='SESSION_EXPIRED'){app().innerHTML=`<div class="card"><div class="err">${esc(e.message)}</div><div style="height:12px"></div><button class="btn" id="rl">ลองใหม่</button></div>`;$('#rl').onclick=()=>location.reload()}}}
window.__vocab={S,W,STAGES,buildSession,distractors,get G(){return G}};
boot();
})();
