const V='kv-1.0.0';
const CORE=['./','index.html','assets/app.css?v=1','assets/config.js?v=1','assets/api.js?v=1','data/words.js?v=1','assets/app.js?v=1','assets/logo.png','assets/fonts/Kanit-Regular.woff','assets/fonts/Kanit-SemiBold.woff','assets/fonts/Fredoka.woff','img/ui/pet_egg.webp','img/ui/pet_chick.webp','img/ui/pet_egret.webp','img/ui/celebrate.webp','img/ui/boss_kwan.webp','img/ui/map_bg.webp','privacy.html','about.html','manifest.webmanifest'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==location.origin)return;
  if(u.pathname.endsWith('/')||u.pathname.endsWith('.html')){e.respondWith(fetch(e.request).then(r=>{const c=r.clone();caches.open(V).then(x=>x.put(e.request,c));return r}).catch(()=>caches.match(e.request).then(r=>r||caches.match('index.html'))));return}
  e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request).then(res=>{if(res.ok){const c=res.clone();caches.open(V).then(x=>x.put(e.request,c))}return res})))});
