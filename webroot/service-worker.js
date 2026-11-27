const CACHE_NAME="integrity-box-ui-v4";
const STATIC_ASSETS=["./","./index.html","./style.css?v=4","./script.js?v=4","./icon.png","./meowna.ttf","./marked.min.js"];
self.addEventListener("install",event=>event.waitUntil(caches.open(CACHE_NAME).then(async cache=>{
  await Promise.all(STATIC_ASSETS.map(async asset=>{try{const response=await fetch(asset,{cache:"reload"});if(response.ok)await cache.put(asset,response)}catch{}}));
}).then(()=>self.skipWaiting())));
self.addEventListener("activate",event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE_NAME).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener("fetch",event=>{
  const req=event.request;
  if(req.method!=="GET"||new URL(req.url).origin!==self.location.origin)return;
  event.respondWith(caches.match(req).then(cached=>{
    if(req.cache==="reload")return fetch(req).then(response=>{const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(req,copy)).catch(()=>{});return response}).catch(()=>cached);
    return cached||fetch(req).then(response=>{const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(req,copy)).catch(()=>{});return response}).catch(()=>cached);
  }));
});
