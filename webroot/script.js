(function(){function logGestureGuard(e){var t=e.target&&e.target.closest&&e.target.closest(".log-scroll,.log-viewer,.log-line,.log-file");if(!t)return;e.stopImmediatePropagation()}document.addEventListener("touchstart",logGestureGuard,true);document.addEventListener("touchmove",logGestureGuard,true);document.addEventListener("touchend",logGestureGuard,true);document.addEventListener("touchcancel",logGestureGuard,true)})();
const MODDIR = `/data/adb/modules/integrity-box/webroot/common_scripts`;
const BOXBRAIN = `/data/adb/Box-Brain`;
const LOGDIR = `${BOXBRAIN}/Integrity-Box-Logs`;
const ANNOUNCEMENT_URL = "https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/announcements/notice.md";
const LOG_PAGE_SIZE = 160;
const UI_CACHE_NAME = "integrity-box-ui-v2";
const UI_SETTINGS_FILE = `${BOXBRAIN}/integrity_box_ui_settings`;
const UI_DEFAULTS = {scale:90,fullscreen:true,backgroundMusic:false,edgeSwipe:true,edgeTap:false,backButton:true,tabSwipe:true,gestureRight:false,openingToasts:true,skipIntro:false,uiStyle:false,uiLayout:"studio",uiCache:true,lang:"en",customFontEnabled:true,tileSize:95};
let uiSettings = {...UI_DEFAULTS};
(function hydrateUISettings(){
  try{
    const saved={
      scale:parseInt(localStorage.getItem("ibUiScale")||"",10),
      fullscreen:localStorage.getItem("ibFullscreen"),
      animatedBackground:localStorage.getItem("ibAnimatedBackground"),
      backgroundMusic:localStorage.getItem("ibBackgroundMusic"),
      edgeSwipe:localStorage.getItem("ibEdgeSwipe"),
      edgeTap:localStorage.getItem("ibEdgeTap"),
      backButton:localStorage.getItem("ibBackButton"),
      tabSwipe:localStorage.getItem("ibTabSwipe"),
      gestureRight:localStorage.getItem("ibGestureRight"),
      openingToasts:localStorage.getItem("ibOpeningToasts"),
      skipIntro:localStorage.getItem("ibSkipIntro"),
      uiStyle:localStorage.getItem("ibUIStyle"),
      uiLayout:localStorage.getItem("ibUILayout"),
      uiCache:localStorage.getItem("ibUICache"),
      lang:localStorage.getItem("ibLang")
    };
    if(Number.isFinite(saved.scale))uiSettings.scale=Math.min(120,Math.max(80,saved.scale));
    for(const key of ["fullscreen","backgroundMusic","edgeSwipe","edgeTap","backButton","tabSwipe","gestureRight","openingToasts","skipIntro","uiStyle","uiCache"])if(saved[key]!==null)uiSettings[key]=saved[key]==="1";
    if(typeof saved.uiLayout==="string"&&["standard","modern","studio"].includes(saved.uiLayout))uiSettings.uiLayout=saved.uiLayout;
    if(typeof saved.lang==="string"&&/^[a-z]{2,3}(?:[-_][A-Za-z]{2,4})?$/i.test(saved.lang))uiSettings.lang=saved.lang;
  }catch{}
})();
function localSetting(key,fallback){try{const v=localStorage.getItem(key);return v===null?fallback:v}catch{return fallback}}
async function loadUISettings(){
  let saved={};
  try{
    const raw=(await runShell(`cat "${UI_SETTINGS_FILE}" 2>/dev/null`)).trim();
    if(raw){
      try{saved=JSON.parse(decodeURIComponent(escape(atob(raw))))||{}}
      catch{try{saved=JSON.parse(raw)||{}}catch{}}
    }
  }catch{}
  try{
    const legacy={scale:parseInt(localStorage.getItem("ibUiScale")||"",10),tileSize:parseInt(localStorage.getItem("ibTileSize")||"",10),customFontEnabled:localStorage.getItem("ibCustomFontEnabled")==="1",fullscreen:localStorage.getItem("ibFullscreen"),animatedBackground:localStorage.getItem("ibAnimatedBackground"),backgroundMusic:localStorage.getItem("ibBackgroundMusic"),openingToasts:localStorage.getItem("ibOpeningToasts"),skipIntro:localStorage.getItem("ibSkipIntro"),uiStyle:localStorage.getItem("ibUIStyle"),uiLayout:localStorage.getItem("ibUILayout"),uiCache:localStorage.getItem("ibUICache"),lang:localStorage.getItem("ibLang")};
    if(saved.scale===undefined&&Number.isFinite(legacy.scale))saved.scale=Math.min(120,Math.max(80,legacy.scale));
    if(saved.uiLayout===undefined&&["standard","modern","studio"].includes(legacy.uiLayout))saved.uiLayout=legacy.uiLayout;
    if(saved.uiLayout===undefined)saved.uiLayout=legacy.uiStyle==="1"?"modern":"standard";
    for(const [k,v] of Object.entries(legacy)){
      if(saved[k]!==undefined||typeof v!=="string"||v===""||k==="scale"||k==="tileSize"||k==="customFontEnabled"||k==="lang"||k==="uiLayout")continue;
      saved[k]=v==="1";
    }
    if(typeof legacy.lang==='string'&&/^[a-z]{2,3}(?:[-_][A-Za-z]{2,4})?$/i.test(legacy.lang))saved.lang=legacy.lang;
  }catch{}
  for(const key of Object.keys(UI_DEFAULTS)){if(saved[key]!==undefined)uiSettings[key]=saved[key]}
  uiSettings.scale=Math.min(120,Math.max(80,parseInt(uiSettings.scale,10)||90));
  uiSettings.tileSize=Math.min(200,Math.max(80,parseInt(uiSettings.tileSize,10)||95));
  uiSettings.customFontEnabled=uiSettings.customFontEnabled!==false;
  if(!["standard","modern","studio"].includes(uiSettings.uiLayout))uiSettings.uiLayout=uiSettings.uiStyle?"modern":"studio";
  uiSettings.uiStyle=uiSettings.uiLayout==="modern";
  document.documentElement.classList.remove("animated-background");
  document.body?.classList.remove("animated-background");
  for(const key of ["fullscreen","backgroundMusic","edgeSwipe","edgeTap","backButton","tabSwipe","gestureRight","openingToasts","skipIntro","uiStyle","uiCache"])uiSettings[key]=!!uiSettings[key];
  if(typeof uiSettings.lang!=="string"||!uiSettings.lang)uiSettings.lang="en";
  const needsInitialSave=!Object.keys(saved).length || Object.keys(UI_DEFAULTS).some(key=>saved[key]===undefined);
  if(needsInitialSave)persistUISettings();
  else syncSettingsToLocalStorage();
  return uiSettings;
}
let settingsSaveTimer=null;
let settingsSavePromise=Promise.resolve();
function syncSettingsToLocalStorage(){
  try{
    localStorage.setItem("ibUiScale",String(uiSettings.scale));
    localStorage.setItem("ibTileSize",String(uiSettings.tileSize));
    localStorage.setItem("ibCustomFontEnabled",uiSettings.customFontEnabled?"1":"0");
    localStorage.setItem("ibFullscreen",uiSettings.fullscreen?"1":"0");
    localStorage.setItem("ibBackgroundMusic",uiSettings.backgroundMusic?"1":"0");
    localStorage.setItem("ibEdgeSwipe",uiSettings.edgeSwipe?"1":"0");
    localStorage.setItem("ibEdgeTap",uiSettings.edgeTap?"1":"0");
    localStorage.setItem("ibBackButton",uiSettings.backButton?"1":"0");
    localStorage.setItem("ibTabSwipe",uiSettings.tabSwipe?"1":"0");
    localStorage.setItem("ibGestureRight",uiSettings.gestureRight?"1":"0");
    localStorage.setItem("ibOpeningToasts",uiSettings.openingToasts?"1":"0");
    localStorage.setItem("ibSkipIntro",uiSettings.skipIntro?"1":"0");
    localStorage.setItem("ibUIStyle",uiSettings.uiLayout==="modern"?"1":"0");
    localStorage.setItem("ibUILayout",uiSettings.uiLayout);
    localStorage.setItem("ibUICache",uiSettings.uiCache?"1":"0");
    localStorage.setItem("ibLang",uiSettings.lang);
  }catch{}
}
function persistUISettings(){
  syncSettingsToLocalStorage();
  if(settingsSaveTimer!==null)clearTimeout(settingsSaveTimer);
  settingsSavePromise=new Promise(resolve=>{
    settingsSaveTimer=setTimeout(()=>{
      settingsSaveTimer=null;
      const snapshot={...uiSettings};
      const encoded=btoa(unescape(encodeURIComponent(JSON.stringify(snapshot))));
      const file=shellQuote(UI_SETTINGS_FILE),dir=shellQuote(BOXBRAIN);
      const command=`mkdir -p ${dir}; tmp=${file}.tmp.$$; printf '%s' '${encoded}' | base64 -d > "$tmp"; if [ ! -f ${file} ] || ! cmp -s "$tmp" ${file}; then mv -f "$tmp" ${file}; else rm -f "$tmp"; fi`;
      runShell(command).catch(()=>{}).finally(resolve);
    },250);
  });
  return settingsSavePromise;
}
async function setUISetting(key,value){uiSettings[key]=value;persistUISettings()}

let selectedLog = null, logLines = [], logOffset = 0, activeLogLevel = "ALL", logSearch = "", logDate = "";
const modalBackdrop = document.getElementById("modal-backdrop"), modalTitle = document.getElementById("modal-title"), modalOutput = document.getElementById("modal-output"), modalClose = document.getElementById("modal-close");
let openingToastsEnabled=true;
const messageMap={kill:{success:"DroidGuard has been restarted",type:"info"},user:{start:"Blacklist Unnecessary Apps",type:"info"},stop:{success:"Switched to Blacklist Mode",type:"info"},start:{success:"Switched to Whitelist Mode",type:"info"},xml:{start:"Scanning xml files..",type:"info"},addon:{start:"Auto Mode is recommended..",type:"info"},conflict:{start:"Choose ROOT implementation..",type:"info"},pixel:{start:"Spoof your device to app",type:"info"},patch:{start:"Opening configuration..",type:"info"},aosp:{success:"Switched to AOSP Keybox",type:"info"},"resetprop.sh":{success:"Done, Reopen detector to check",type:"info"},selinux:{success:"Spoofed to Enforcing",type:"info"},piffork:{start:"All changes will be applied immediately",type:"info"},propspoofer:{start:"These will be applied till reboot",type:"info"},nogms:{success:"Reboot to apply changes",type:"info"},yesgms:{start:"Reboot to apply changes",type:"info"},"key.sh":{success:"Keybox has been updated",type:"info"},flags:{start:"These requires Reboot / Action",type:"info"},ctrl:{start:"For those using ROM inbuilt spoofing",type:"info"},"force_override.sh":{start:"Done",type:"info"},pif:{start:"You can update fingerprint without internet",type:"info"},vending:{start:"This will clear data of Play Services & Store",type:"info"},zygisknext:{start:"Whatever you say cutie",type:"info"},cache:{start:"This will delete temporary unnecessary files",type:"info"},hide:{start:"This will hide basic sus paths",type:"info"},scanner:{start:"Click on Run Scan",success:"Detection Complete",type:"info"},support:{start:"Become a Supporter",type:"info"},report:{start:"What's wrong buddy?",type:"info"},status:{start:"Informs you about keybox & fingerprint validity",type:"info"},"hma.sh":{success:"Done",type:"info"},ulock:{success:"Done",type:"info"},nuke:{start:"Coming Soon",type:"info"},spoofing:{start:"These are for custom ROM users",type:"info"},downloader:{start:"Some useful stuff you may need",type:"info"},hash:{start:"Paste your boot hash buddy",success:"Boot hash operation complete",type:"success"}};
function popup(msg,type="info"){try{if(typeof window.toast==="function"){window.toast(String(msg));return}if(window.kernelsu&&typeof window.kernelsu.toast==="function"){window.kernelsu.toast(String(msg));return}if(typeof ksu==="object"&&typeof ksu.toast==="function"){ksu.toast(String(msg));return}}catch{}const n=document.createElement("div");n.className="webui-popup";n.textContent=msg;const colors={error:"#FF4C4C",success:"#0ED000",info:"#1592FF",warn:"#FFB500"};const bg=colors[type]||colors.info;n.style.background=bg+"dd";n.style.color=type==="success"?"#0a1f0f":"#fff";document.body.appendChild(n);requestAnimationFrame(()=>{n.style.top="24px";n.style.opacity="1"});setTimeout(()=>{n.style.top="-80px";n.style.opacity="0";setTimeout(()=>n.remove(),400)},2800)}
async function runShell(cmd){
  if(!cmd)throw new Error("Empty shell command");
  const api=(typeof window.ksu!=="undefined"&&window.ksu)||(typeof window.kernelsu!=="undefined"&&window.kernelsu)||(typeof ksu!=="undefined"&&ksu)||(typeof kernelsu!=="undefined"&&kernelsu);
  if(!api||typeof api.exec!=="function")throw new Error("KSU API unavailable");
  return new Promise((resolve,reject)=>{
    const cb=`__ib_exec_${Date.now()}_${Math.random().toString(36).slice(2)}`;
    let settled=false;
    const finish=(ok,value)=>{if(settled)return;settled=true;try{delete window[cb]}catch{};ok?resolve(String(value??"").replace(/\r/g,"")):reject(value instanceof Error?value:new Error(String(value||"Shell failed")))};
    window[cb]=(code,stdout,stderr)=>{
      const exit=typeof code==="number"?code:Number(code||0);
      finish(exit===0,exit===0?(stdout||""):(stderr||stdout||"Shell failed"));
    };
    try{
      const result=api.exec(cmd,"{}",cb);
      if(result&&typeof result.then==="function"){
        result.then(value=>finish(true,value?.stdout??value??""),error=>finish(false,error));
      }
    }catch(e){finish(false,e)}
    setTimeout(()=>{if(!settled)finish(false,new Error("Shell command timed out"))},15000);
  });
}
async function setFullScreen(enabled){
  const next=!!enabled,changed=uiSettings.fullscreen!==next;
  uiSettings.fullscreen=next;
  if(changed)await persistUISettings();
  try{
    if(next){
      try{await runShell(`[ -d ${shellQuote(BOXBRAIN)} ] || mkdir -p ${shellQuote(BOXBRAIN)}; [ -e ${shellQuote(`${BOXBRAIN}/fullscreen_enabled`)} ] || : > ${shellQuote(`${BOXBRAIN}/fullscreen_enabled`)}`)}catch{}
      if(window.kernelsu?.fullScreen)await window.kernelsu.fullScreen(true);
      else if(window.fullScreen)await window.fullScreen(true);
      else if(typeof ksu!=="undefined"&&ksu?.fullScreen)await ksu.fullScreen(true);
      else if(document.documentElement.requestFullscreen)await document.documentElement.requestFullscreen().catch(()=>{});
    }else{
      try{await runShell(`[ ! -e ${shellQuote(`${BOXBRAIN}/fullscreen_enabled`)} ] || rm -f ${shellQuote(`${BOXBRAIN}/fullscreen_enabled`)}`)}catch{}
      if(document.fullscreenElement&&document.exitFullscreen)await document.exitFullscreen().catch(()=>{});
      try{if(window.kernelsu?.fullScreen)await window.kernelsu.fullScreen(false);else if(window.fullScreen)await window.fullScreen(false);else if(typeof ksu!=="undefined"&&ksu?.fullScreen)await ksu.fullScreen(false)}catch{}
    }
  }catch{}
}
async function getSavedFullscreen(){return !!uiSettings.fullscreen}
async function readFlag(path,defaultValue=false){try{return(await runShell(`[ -f "${path}" ] && echo 1 || echo 0`)).trim()==="1"}catch{return defaultValue}}
async function readToggle(name,defaultValue=true){return (await readFlag(`${BOXBRAIN}/${name}_disabled`,false))?false:defaultValue}
async function writeToggle(name,enabled,defaultValue=true){await runShell(enabled===defaultValue?`rm -f "${BOXBRAIN}/${name}_disabled"`:`touch "${BOXBRAIN}/${name}_disabled"`)}
async function checkGestureConfig(){return{gestureRight:!!uiSettings.gestureRight,backButton:!!uiSettings.backButton,edgeGesture:!!uiSettings.edgeSwipe,edgeTap:!!uiSettings.edgeTap,tabSwipe:!!uiSettings.tabSwipe}}
let iframeHistoryActive=false;
let iframeOpening=false;
let iframeCloseHandler=null;
let iframeHistoryToken="";
let iframeOrigin={tab:"home",subtab:"status"};
function restoreMainHome(){
  document.body.classList.remove("iframe-open","extract-open");
  document.documentElement.classList.remove("iframe-open");
  document.querySelectorAll(".iframe-host-layer,.iframe-back-btn,body > [data-iframe-edge=\"1\"]").forEach(e=>e.remove());
  const targetTab=iframeOrigin.tab||"home";
  document.querySelectorAll(".tab-panel").forEach(panel=>{
    const active=panel.id==="tab-"+targetTab;
    panel.classList.toggle("active",active);
    panel.classList.remove("enter-left","enter-right","exit-left","exit-right");
  });
  document.querySelectorAll(".nav-item").forEach(item=>item.classList.toggle("active",item.dataset.tab===targetTab));
  if(targetTab==="home")try{activateHomeSubtab(iframeOrigin.subtab||"status")}catch{}
  document.activeElement?.blur?.();
  window.scrollTo?.(0,0);
}
function cleanupIframeState(){
  document.body.classList.remove("iframe-open");
  document.documentElement.classList.remove("iframe-open");
  document.querySelectorAll(".iframe-host-layer,.iframe-back-btn,body > [data-iframe-edge=\"1\"]").forEach(e=>e.remove());
  document.activeElement?.blur?.();
}
function enterIframeHistory(){
  iframeHistoryToken="ib-iframe-"+Date.now()+"-"+Math.random().toString(36).slice(2,8);
  try{location.hash=iframeHistoryToken}catch{}
  iframeHistoryActive=true;
}
function leaveIframeHistory(){
  if(!iframeHistoryActive)return;
  const token=iframeHistoryToken;
  iframeHistoryActive=false;
  iframeHistoryToken="";
  if(location.hash==="#"+token){
    try{history.back()}catch{}
  }
}
async function openIframe(url,options={}){
  if(!url||iframeOpening||document.getElementById("active-iframe"))return;
  iframeOpening=true;
  const external=!!options.external;
  const config={gestureRight:false,backButton:false,edgeGesture:!external,edgeTap:!external};
  try{
    Object.assign(config,await checkGestureConfig());
    if(external){config.edgeGesture=false;config.edgeTap=false;config.backButton=false}
    createIframeUI(url,config);
  }catch{
    createIframeUI(url,config);
  }finally{
    iframeOpening=false;
  }
}
function createIframeUI(url,config){
  iframeOrigin={tab:document.querySelector(".nav-item.active")?.dataset.tab||"home",subtab:document.querySelector(".home-subtab.active")?.dataset.subtab||"status"};
  const iframeLayer=document.createElement("div");
  iframeLayer.className="iframe-host-layer";
  iframeLayer.dataset.iframeHost="1";
  const iframe=document.createElement("iframe");
  iframe.id="active-iframe";
  iframe.title="Integrity Box Support";
  iframe.setAttribute("allowfullscreen","");
  iframe.setAttribute("webkitallowfullscreen","");
  iframe.setAttribute("scrolling","auto");
  iframe.setAttribute("allow","clipboard-read; clipboard-write; fullscreen");
  iframe.setAttribute("referrerpolicy","no-referrer-when-downgrade");
  Object.assign(iframeLayer.style,{position:"fixed",inset:"0",width:"100vw",height:"100dvh",zIndex:9998,background:"transparent",overflow:"hidden",pointerEvents:"auto"});
  Object.assign(iframe.style,{position:"absolute",inset:"0",width:"100%",height:"100%",border:"none",background:"transparent",display:"block",userSelect:"text",webkitUserSelect:"text",touchAction:"auto",pointerEvents:"auto",opacity:"1",visibility:"visible",transition:"none"});
  iframeLayer.appendChild(iframe);
  iframe.addEventListener("load",()=>{
    if(localStorage.getItem("ibCustomFontEnabled")==="1")applyCustomFont(true);
  });
  document.body.classList.add("iframe-open");
  document.documentElement.classList.add("iframe-open");
  document.body.appendChild(iframeLayer);
  iframe.src=url;
  enterIframeHistory();

  const useFloatingBack=!!config.backButton;
  const useEdgeGesture=!!config.edgeGesture;
  const useEdgeTap=!!config.edgeTap;
  const isRight=!!config.gestureRight;
  let edge=null,backBtn=null,closed=false;

  const closeIframe=(fromHistory=false)=>{
    if(closed)return;
    closed=true;
    const token=iframeHistoryToken;
    iframeHistoryActive=false;
    iframeHistoryToken="";
    iframeCloseHandler=null;
    try{window.removeEventListener("ibAnimatedBackgroundChange",syncIframeTheme)}catch{}
    iframe.src="about:blank";
    iframe.remove();
    iframeLayer.remove();
    edge?.remove();
    backBtn?.remove();
    cleanupIframeState();
    restoreMainHome();
    if(!fromHistory&&location.hash==="#"+token){
      try{history.back()}catch{}
    }
  };

  iframeCloseHandler=closeIframe;

  if(useEdgeGesture||useEdgeTap){
    edge=document.createElement("div");
    edge.dataset.iframeEdge="1";
    edge.setAttribute("aria-hidden","true");
    Object.assign(edge.style,{position:"absolute",top:"0",[isRight?"right":"left"]:"0",width:"34px",height:"100%",zIndex:"100000000",background:"transparent",pointerEvents:"auto",touchAction:"none",userSelect:"none",webkitUserSelect:"none"});
    iframeLayer.appendChild(edge);
    let startX=0,startY=0,startTime=0;
    const onStart=e=>{const t=e.touches?.[0]||e;startX=t.clientX;startY=t.clientY;startTime=Date.now()};
    const onEnd=e=>{
      if(closed)return;
      const t=e.changedTouches?.[0]||e;
      const dx=t.clientX-startX;
      const diff=isRight?-dx:dx;
      const dy=Math.abs(t.clientY-startY);
      const dt=Date.now()-startTime;
      const tap=useEdgeTap&&Math.abs(dx)<18&&dy<28&&dt<500;
      const swipe=useEdgeGesture&&diff>45&&dy<Math.max(70,diff*1.25)&&dt<500;
      if(tap||swipe){e.preventDefault?.();e.stopPropagation?.();closeIframe()}
    };
    edge.addEventListener("touchstart",onStart,{passive:true});
    edge.addEventListener("touchend",onEnd,{passive:false});
    edge.addEventListener("pointerdown",onStart,{passive:true});
    edge.addEventListener("pointerup",onEnd,{passive:false});
    edge.addEventListener("click",e=>{if(useEdgeTap&&!closed)closeIframe()});
  }

  if(useFloatingBack){
    backBtn=document.createElement("button");
    backBtn.type="button";
    backBtn.className="iframe-back-btn";
    backBtn.setAttribute("aria-label","Back");
    backBtn.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14.7 5.3 8 12l6.7 6.7"/><path d="M8.5 12H20"/></svg>';
    backBtn.style[isRight?"left":"right"]="16px";
    const back=event=>{event?.preventDefault?.();event?.stopPropagation?.();closeIframe()};
    backBtn.addEventListener("click",back);
    document.body.appendChild(backBtn);
  }
}
window.addEventListener("hashchange",()=>{
  if(iframeCloseHandler&&iframeHistoryActive&&location.hash!=="#"+iframeHistoryToken){
    iframeCloseHandler(true);
  }
});
window.addEventListener("popstate",()=>{
  if(iframeCloseHandler&&iframeHistoryActive&&location.hash!=="#"+iframeHistoryToken){
    iframeCloseHandler(true);
  }
});
window.runShellFromIframe=async cmd=>runShell(cmd);
async function readExpiry(file){return(await runShell(`grep -i 'Estimated Expiry' "${file}" 2>/dev/null | head -n1 | cut -d':' -f2-`)).trim()}
const KEYBOX_STATUS_FILE = `${BOXBRAIN}/status.json`;
const ACTIVE_KEYBOX_FILE = `/data/adb/tricky_store/keybox.xml`;
let keyboxStatusPromise = null;
function keyboxNormalizeSerial(value){
  let serial=String(value||"").trim().toLowerCase().replace(/^0x/,"").replace(/[:\s-]/g,"");
  serial=serial.replace(/^0+/,"");
  return serial||"0";
}
function keyboxReadAsn1(bytes,offset){
  if(offset>=bytes.length)throw new Error("Unexpected end of certificate");
  const tag=bytes[offset++];
  if(offset>=bytes.length)throw new Error("Invalid ASN.1 length");
  let length=bytes[offset++];
  if(length&0x80){
    const count=length&0x7f;
    if(!count||count>4||offset+count>bytes.length)throw new Error("Invalid ASN.1 length encoding");
    length=0;
    for(let i=0;i<count;i++)length=length*256+bytes[offset++];
  }
  const contentStart=offset,end=contentStart+length;
  if(end>bytes.length)throw new Error("Truncated certificate data");
  return{tag,contentStart,length,end};
}
function keyboxSerialFromCertificate(encoded){
  const binary=atob(String(encoded||"").replace(/[^A-Za-z0-9+/=]/g,""));
  const bytes=new Uint8Array(binary.length);
  for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);
  const cert=keyboxReadAsn1(bytes,0);
  if(cert.tag!==0x30)throw new Error("Invalid X.509 certificate");
  const tbs=keyboxReadAsn1(bytes,cert.contentStart);
  if(tbs.tag!==0x30)throw new Error("Invalid TBSCertificate");
  let offset=tbs.contentStart,field=keyboxReadAsn1(bytes,offset);
  if(field.tag===0xa0){offset=field.end;field=keyboxReadAsn1(bytes,offset)}
  if(field.tag!==0x02||!field.length)throw new Error("Certificate serial number not found");
  let serial="";
  for(let i=field.contentStart;i<field.end;i++)serial+=bytes[i].toString(16).padStart(2,"0");
  return keyboxNormalizeSerial(serial);
}
function keyboxCertificateExpiry(encoded){
  const source=String(encoded||""),pem=source.match(/-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----/);
  const payload=pem?pem[1]:source.replace(/<[^>]*>/g,"");
  const binary=atob(payload.replace(/[^A-Za-z0-9+/=]/g,""));
  const bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);
  const cert=keyboxReadAsn1(bytes,0),tbs=keyboxReadAsn1(bytes,cert.contentStart);
  let offset=tbs.contentStart,field=keyboxReadAsn1(bytes,offset);
  if(field.tag===0xa0){offset=field.end;field=keyboxReadAsn1(bytes,offset)}
  offset=field.end; // serial
  offset=keyboxReadAsn1(bytes,offset).end; // signature
  offset=keyboxReadAsn1(bytes,offset).end; // issuer
  const validity=keyboxReadAsn1(bytes,offset);
  if(validity.tag!==0x30)throw new Error("Certificate validity field not found");
  const notBefore=keyboxReadAsn1(bytes,validity.contentStart),notAfter=keyboxReadAsn1(bytes,notBefore.end);
  const raw=String.fromCharCode(...bytes.slice(notAfter.contentStart,notAfter.end));
  let date;
  if(notAfter.tag===0x17){const yy=Number(raw.slice(0,2)),year=yy>=50?1900+yy:2000+yy;date=new Date(Date.UTC(year,Number(raw.slice(2,4))-1,Number(raw.slice(4,6)),Number(raw.slice(6,8)),Number(raw.slice(8,10)),Number(raw.slice(10,12))));}
  else if(notAfter.tag===0x18){date=new Date(Date.UTC(Number(raw.slice(0,4)),Number(raw.slice(4,6))-1,Number(raw.slice(6,8)),Number(raw.slice(8,10)),Number(raw.slice(10,12)),Number(raw.slice(12,14))));}
  else throw new Error("Unsupported certificate expiry format");
  if(isNaN(date.getTime()))throw new Error("Invalid certificate expiry date");
  return date;
}
function* keyboxCertificateBlocks(certificateText){
  const source=String(certificateText||""),pem=/-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----/g;
  let match,found=false;
  while((match=pem.exec(source))){found=true;yield match[1]}
  if(!found){const raw=source.replace(/<[^>]*>/g,"").trim();if(raw)yield raw}
}
function findKeyboxRevokedSerial(xml,entries){
  const doc=new DOMParser().parseFromString(String(xml||""),"application/xml");
  if(doc.getElementsByTagName("parsererror").length)throw new Error("Keybox XML is malformed");
  let certificates=Array.from(doc.getElementsByTagNameNS("*","Certificate"));
  if(!certificates.length)certificates=Array.from(doc.getElementsByTagName("Certificate"));
  if(!certificates.length)throw new Error("No certificates found in keybox");
  let hasEntries=false;
  for(const key in entries){if(Object.prototype.hasOwnProperty.call(entries,key)){hasEntries=true;break}}
  const isRevoked=serial=>{
    if(Object.prototype.hasOwnProperty.call(entries,serial))return true;
    for(const listedSerial in entries){
      if(Object.prototype.hasOwnProperty.call(entries,listedSerial)&&keyboxNormalizeSerial(listedSerial)===serial)return true;
    }
    return false;
  };
  let serialCount=0,parseErrors=0,lastError="",expiredCertificate=null,latestExpiry=null;
  for(let i=0;i<certificates.length;i++){
    let foundSerial=false;
    try{
      for(const encoded of keyboxCertificateBlocks(certificates[i].textContent||"")){
        foundSerial=true;serialCount++;
        const serial=keyboxSerialFromCertificate(encoded);
        if(isRevoked(serial))return{serial,serialCount,certificateIndex:i+1};
        try{
          const expiry=keyboxCertificateExpiry(encoded);
          if(!latestExpiry||expiry<latestExpiry.expiry)latestExpiry={expiry,serial,certificateIndex:i+1};
          if(expiry<=new Date()&&(!expiredCertificate||expiry<expiredCertificate.expiry))expiredCertificate={expiry,serial,certificateIndex:i+1};
        }catch(expiryError){console.warn("Certificate expiry parsing skipped",expiryError)}
      }
      if(!foundSerial)throw new Error("Certificate data is empty");
    }catch(error){parseErrors++;lastError=String(error?.message||error);continue}
  }
  if(!serialCount)throw new Error(lastError||"No certificate serials could be extracted");
  if(parseErrors)throw new Error(`${parseErrors} certificate(s) could not be parsed`);
  if(expiredCertificate)return{expired:true,expiry:expiredCertificate.expiry,serial:expiredCertificate.serial,certificateIndex:expiredCertificate.certificateIndex,serialCount};
  if(!hasEntries)return{empty:true,serialCount,latestExpiry};
  return{serialCount,latestExpiry};
}
async function fetchKeyboxStatus(){
  const readWithTimeout=async command=>{
    let timer;
    try{return await Promise.race([runShell(command),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error("Keybox check timed out")),12000)})])}
    finally{if(timer)clearTimeout(timer)}
  };
  try{
    const statusRaw=await readWithTimeout(`[ -r ${shellQuote(KEYBOX_STATUS_FILE)} ] && cat ${shellQuote(KEYBOX_STATUS_FILE)}`);
    if(!String(statusRaw||"").trim())return{status:"ACTION",label:"Run action once"};
    const config=JSON.parse(String(statusRaw));
    if(!config||typeof config!=="object"||Array.isArray(config))throw new Error("Invalid status.json configuration");
    if(config.entries===undefined&&Object.keys(config).length===0)return{status:"ACTION",label:"Run action once"};
    if(!config.entries||typeof config.entries!=="object"||Array.isArray(config.entries))throw new Error("Invalid status.json: entries configuration is missing");
    if(Object.keys(config.entries).length===0)return{status:"ACTION",label:"Run action once"};
    const keyboxXml=await readWithTimeout(`[ -r ${shellQuote(ACTIVE_KEYBOX_FILE)} ] && cat ${shellQuote(ACTIVE_KEYBOX_FILE)}`);
    const result=findKeyboxRevokedSerial(keyboxXml,config.entries);
    if(result.empty)return{status:"ACTION",label:"Run action once"};
    if(result.serial)return{status:"REVOKED",label:"Keybox is revoked",serial:result.serial};
    if(result.expired)return{status:"EXPIRED",label:"Keybox expired",expiry:result.expiry.toISOString(),serial:result.serial};
    return{status:"VALID",label:"Keybox is valid",serialCount:result.serialCount,expiry:result.latestExpiry?.expiry?.toISOString()||null};
  }catch(error){
    console.warn("Keybox integrity check failed",error);
    return{status:"ERROR",label:"Error checking keybox",detail:String(error?.message||error)};
  }
}
function setStatus(id,text){const e=document.getElementById("status-"+id);if(e)e.textContent=text}
function applyIntegrity(result){
  const card=document.getElementById("home-integrity-card"),value=document.getElementById("home-status-integrity");
  const title={VALID:"Keybox is valid",REVOKED:"Keybox is revoked",EXPIRED:"Keybox expired",ACTION:"Run action once",ERROR:"Error checking keybox"}[result.status]||"Error checking keybox";
  if(value){
    value.textContent=title;value.dataset.integrityStatus=result.status||"ERROR";value.title=result.detail||"";
    let expiryLine=document.getElementById("home-integrity-expiry");
    if(!expiryLine){expiryLine=document.createElement("span");expiryLine.id="home-integrity-expiry";expiryLine.className="home-integrity-expiry";value.insertAdjacentElement("afterend",expiryLine)}
    if(result.status==="VALID"&&result.expiry){
      const date=new Date(result.expiry),now=new Date();
      if(!isNaN(date.getTime())){
        expiryLine.textContent="Valid until "+date.toLocaleDateString(undefined,{day:"numeric",month:"long",year:"numeric"});
        let countdown=document.getElementById("home-integrity-countdown");
        if(!countdown){countdown=document.createElement("span");countdown.id="home-integrity-countdown";countdown.className="home-integrity-countdown";expiryLine.insertAdjacentElement("afterend",countdown)}
        const remaining=Math.max(0,Math.ceil((date.getTime()-now.getTime())/86400000));
        countdown.textContent=remaining===0?"It may stop working within 24 hours.":"Play Integrity will fail anytime in "+remaining+" day"+(remaining===1?"":"s")+".";
        countdown.hidden=false;
      }else{expiryLine.textContent="";expiryLine.hidden=true;const countdown=document.getElementById("home-integrity-countdown");if(countdown){countdown.textContent="";countdown.hidden=true}}
      expiryLine.hidden=!expiryLine.textContent;
    }
    else{expiryLine.textContent="";expiryLine.hidden=true;const countdown=document.getElementById("home-integrity-countdown");if(countdown){countdown.textContent="";countdown.hidden=true}}
  }
  if(card){
    card.classList.remove("is-good","is-warn","is-bad","is-offline","is-expired");
    if(result.status==="VALID")card.classList.add("is-good");
    else if(result.status==="REVOKED")card.classList.add("is-bad");
    else if(result.status==="EXPIRED")card.classList.add("is-expired");
    else if(result.status==="ACTION")card.classList.add("is-warn");
    else card.classList.add("is-offline");
  }
}
async function refreshKeyboxStatus(force=false){
  if(keyboxStatusPromise)return keyboxStatusPromise;
  const age=Date.now()-(window.__ibKeyboxStatusAt||0);
  if(!force&&window.__ibKeyboxStatus&&age<300000){
    setStatus("keybox",window.__ibKeyboxStatus.label);
    applyIntegrity(window.__ibKeyboxStatus);
    return window.__ibKeyboxStatus;
  }
  const value=document.getElementById("home-status-integrity");
  if(value)value.textContent="Checking keybox status…";
  keyboxStatusPromise=(async()=>{
    const result=await fetchKeyboxStatus();
    window.__ibKeyboxStatus=result;
    window.__ibKeyboxStatusAt=Date.now();
    setStatus("keybox",result.label);
    applyIntegrity(result);
    return result;
  })().catch(error=>{
    const result={status:"ERROR",label:"Error checking keybox",detail:String(error?.message||error)};
    window.__ibKeyboxStatus=result;window.__ibKeyboxStatusAt=Date.now();
    setStatus("keybox",result.label);applyIntegrity(result);return result;
  }).finally(()=>{keyboxStatusPromise=null});
  return keyboxStatusPromise;
}
async function updateModuleVersion(){
  const target=document.getElementById("module-version");
  if(!target)return;
  target.textContent="";
  target.classList.add("hidden");
  try{
    const raw=await runShell("cat -- '/data/adb/modules/integrity-box/module.prop'");
    const line=String(raw||"").split(/\r?\n/).find(item=>/^version\s*=/.test(item));
    const version=line?line.slice(line.indexOf("=")+1).trim():"";
    if(!version)throw new Error("Module version is missing");
    target.textContent="| "+version;
    target.classList.remove("hidden");
    target.setAttribute("aria-label","Module version "+version);
    if(document.fonts?.load)document.fonts.load('16px "meowna"').catch(()=>{});
    return version;
  }catch(error){
    console.warn("Unable to read Integrity Box module version:",error);
    target.textContent="";
    target.classList.add("hidden");
    return "";
  }
}
async function overviewPackageVersion(pkg){
  const raw=(await runShell(`dumpsys package '${pkg}' 2>/dev/null | grep -m 4 -E 'versionCode=|versionName='`)).trim();
  const code=(raw.match(/versionCode=([^\s]+)/)||[])[1]||"Unknown";
  const name=(raw.match(/versionName=([^\s]+)/)||[])[1]||"Unknown";
  if(name==="Unknown"&&code==="Unknown")throw new Error("Package unavailable");
  return {name,code,key:name+"|"+code};
}
async function overviewTrackApps(){
  const file=`${BOXBRAIN}/system_overview_versions.json`;
  let history={};
  try{
    const raw=(await runShell(`cat '${file}' 2>/dev/null || true`)).trim();
    if(raw){
      const parsed=JSON.parse(raw);
      if(parsed&&typeof parsed==="object"&&!Array.isArray(parsed))history=parsed;
    }
  }catch(error){console.warn("Version history unavailable; a new baseline will be created",error)}

  const packageTargets=[["playStore","com.android.vending","store"],["playServices","com.google.android.gms","gms"]];
  const results=await Promise.all(packageTargets.map(async([key,pkg,prefix])=>{
    try{
      const current=await overviewPackageVersion(pkg);
      let entry=history[key];
      if(!entry||typeof entry!=="object"||Array.isArray(entry))entry={current:null,previous:[]};
      if(!Array.isArray(entry.previous))entry.previous=[];
      if(entry.current&&typeof entry.current==="object"){
        entry.current.name=String(entry.current.name||"Unknown");
        entry.current.code=String(entry.current.code||"Unknown");
        entry.current.key=entry.current.key||`${entry.current.name}|${entry.current.code}`;
      }
      let changed=false,baseline=false;
      if(!entry.current){
        entry.current={...current,observedAt:new Date().toISOString()};
        baseline=true;
      }else if(entry.current.key!==current.key){
        const previous={...entry.current};
        entry.previous=[previous,...entry.previous]
          .filter((item,index,array)=>item&&array.findIndex(x=>x?.key===item.key)===index)
          .slice(0,5);
        entry.current={...current,observedAt:new Date().toISOString()};
        changed=true;
      }
      history[key]=entry;
      return {prefix,current,entry,changed,baseline};
    }catch(error){
      console.warn(`Could not query ${pkg}`,error);
      return {prefix,error};
    }
  }));

  try{
    const encoded=btoa(unescape(encodeURIComponent(JSON.stringify(history,null,2))));
    await runShell(`mkdir -p '${BOXBRAIN}' && printf '%s' '${encoded}' > '${file}.tmp.b64' && base64 -d '${file}.tmp.b64' > '${file}.tmp' && mv '${file}.tmp' '${file}' && rm -f '${file}.tmp.b64'`);
    window.__systemOverviewVersionHistory=history;
  }catch(error){
    console.warn("Could not persist System Overview version history",error);
    popup("Version history could not be saved","error");
  }

  const renderHistory=(container,entry,current,changed,baseline)=>{
    if(!container)return;
    container.replaceChildren();
    if(baseline){
      const note=document.createElement("span");
      note.className="overview-history-note";
      note.textContent="Initial version saved. Future updates will be tracked here.";
      container.append(note);
      return;
    }
    const previous=entry?.previous?.[0];
    if(!previous){
      const note=document.createElement("span");
      note.className="overview-history-note";
      note.textContent="No version update recorded since the initial baseline.";
      container.append(note);
      return;
    }
    const makeVersionCard=(labelText,version)=>{
      const card=document.createElement("div");
      card.className="overview-history-side";
      const label=document.createElement("small");
      label.textContent=labelText;
      const value=document.createElement("strong");
      value.textContent=version?.name||"Unknown";
      const code=document.createElement("span");
      code.textContent=`Version code ${version?.code||"Unknown"}`;
      card.append(label,value,code);
      return card;
    };
    container.append(makeVersionCard("PREVIOUS VERSION",previous),makeVersionCard("CURRENT VERSION",current));
  };

  results.forEach(({prefix,current,entry,changed,baseline,error})=>{
    const get=id=>document.getElementById(`overview-${id}`);
    const version=get(`${prefix}-current`),code=get(`${prefix}-code`),state=get(`${prefix}-state`),historyEl=get(`${prefix}-history`);
    if(error){
      if(version)version.textContent="Unavailable";
      if(code)code.textContent="—";
      if(state){state.textContent="Unavailable";state.dataset.state="unknown"}
      if(historyEl)historyEl.textContent="Version information could not be read";
      return;
    }
    if(version)version.textContent=current.name;
    if(code)code.textContent=current.code;
    if(state){
      const hasRecordedChange=Array.isArray(entry.previous)&&entry.previous.length>0;
      state.textContent=baseline?"Baseline saved":hasRecordedChange?"Version changed":"No change";
      state.dataset.state=baseline?"baseline":hasRecordedChange?"changed":"stable";
    }
    renderHistory(historyEl,entry,current,changed,baseline);
  });
}
async function overviewDetectWebView(){
  const set=(id,value)=>{const e=document.getElementById("overview-"+id);if(e)e.textContent=value};
  try{
    const info=(await runShell("cmd webviewupdate getCurrentWebViewPackage 2>/dev/null")).trim();
    const m=info.match(/\(([A-Za-z0-9_.]+),\s*([0-9][^\s)]*)\)/);
    if(m){set("webview-package",m[1]);set("webview-current",m[2]);const state=document.getElementById("overview-webview-state");if(state){state.textContent="Active";state.dataset.state="stable"}return}
  }catch{}
  for(const pkg of ["com.google.android.webview","com.android.webview","com.android.chrome"]){
    try{const v=await overviewPackageVersion(pkg);set("webview-package",pkg);set("webview-current",v.name);const state=document.getElementById("overview-webview-state");if(state){state.textContent="Installed";state.dataset.state="stable"}return}catch{}
  }
  set("webview-package","Not detected");set("webview-current","Unavailable");const state=document.getElementById("overview-webview-state");if(state){state.textContent="Unavailable";state.dataset.state="unknown"}
}
async function overviewCountUserApps(){
  const el=document.getElementById("overview-user-apps");
  if(!el)return;
  try{
    const raw=await runShell("pm list packages -3 2>/dev/null | awk 'END { print NR+0 }'");
    const count=parseInt(String(raw).trim(),10);
    el.textContent=Number.isFinite(count)?String(count):"Unavailable";
  }catch(error){
    console.warn("Could not count user apps",error);
    el.textContent="Unavailable";
  }
}
async function overviewLoadModules(){
  const list=document.getElementById("overview-modules"),count=document.getElementById("overview-module-count");
  if(!list)return;
  try{
    const raw=await runShell(`for f in /data/adb/modules/*/module.prop; do
      [ -f "$f" ] || continue
      d=\${f%/module.prop}; id=\${d##*/}
      n=$(awk -F= '/^name=/{print substr($0,index($0,"=")+1);exit}' "$f")
      v=$(awk -F= '/^version=/{print substr($0,index($0,"=")+1);exit}' "$f")
      [ -n "$n" ] || n=$id
      [ -n "$v" ] || v=Unknown
      printf '%s\\t%s\\t%s\\n' "$id" "$n" "$v"
    done`);
    const modules=raw.split(/\r?\n/).filter(Boolean).map(line=>{
      const p=line.split("\t");
      return{id:p[0]||"unknown",name:p[1]||p[0]||"Unknown module",version:p.slice(2).join("\t")||"Unknown"};
    }).sort((a,b)=>a.name.localeCompare(b.name));
    list.replaceChildren();
    if(!modules.length){
      const empty=document.createElement("div");empty.className="overview-module-empty";empty.textContent="No installed modules found in /data/adb/modules.";
      list.append(empty);count.textContent="0 modules";window.__systemOverviewModules=[];return;
    }
    modules.forEach(module=>{
      const card=document.createElement("article");card.className="overview-module-card";
      const top=document.createElement("div");top.className="overview-module-top";
      const name=document.createElement("strong");name.className="overview-module-name";name.textContent=module.name;
      const version=document.createElement("span");version.className="overview-module-version";version.textContent=module.version;
      top.append(name,version);card.append(top);list.append(card);
    });
    count.textContent=`${modules.length} installed`;
    window.__systemOverviewModules=modules;
  }catch(error){
    console.warn("Could not read installed modules",error);
    list.replaceChildren();
    const empty=document.createElement("div");empty.className="overview-module-empty";empty.textContent="Unable to read module.prop files. Check root shell access.";
    list.append(empty);count.textContent="Unavailable";
  }
}
async function updateDashboard(force=false){
  const now=Date.now();
  if(!force&&window.__ibOverviewLoaded&&now-(window.__ibOverviewLastRun||0)<30000)return;
  if(window.__ibOverviewBusy)return;
  window.__ibOverviewBusy=true;
  const refresh=document.getElementById("extract-refresh"),stamp=document.getElementById("overview-last-updated");
  if(refresh)refresh.disabled=true;
  try{
  if(stamp)stamp.textContent="Updating diagnostics…";
  let props={};
  try{
    const raw=await runShell(`for p in ro.product.manufacturer ro.product.model ro.build.version.release ro.build.display.id ro.build.version.incremental ro.product.cpu.abi ro.soc.model ro.hardware ro.build.fingerprint ro.build.version.security_patch ro.vendor.build.security_patch ro.vendor.build.version.security_patch; do printf '%s=' "$p"; getprop "$p"; done; printf 'KERNEL='; uname -r; printf 'SELINUX='; getenforce 2>/dev/null || echo Unknown; printf 'UPTIME='; awk '{printf "%.0f\\n",$1}' /proc/uptime`);
    raw.split(/\r?\n/).forEach(line=>{const i=line.indexOf("=");if(i>0)props[line.slice(0,i)]=line.slice(i+1).trim()});
    const put=(id,value)=>{const e=document.getElementById("overview-"+id);if(e)e.textContent=value||"Unavailable"};
    put("device",[props["ro.product.manufacturer"],props["ro.product.model"]].filter(Boolean).join(" "));
    put("android",props["ro.build.version.release"]);
    put("build",props["ro.build.display.id"]||props["ro.build.version.incremental"]);
    put("arch",props["ro.product.cpu.abi"]);
    put("cpu",props["ro.soc.model"]||props["ro.hardware"]);
    put("kernel",props.KERNEL);put("root","Detecting…");put("selinux",props.SELINUX);
    put("buildpatch",props["ro.build.version.security_patch"]);
    put("vendorpatch",props["ro.vendor.build.security_patch"]||props["ro.vendor.build.version.security_patch"]);
    put("fingerprint",props["ro.build.fingerprint"]);
    const sec=Math.max(0,parseInt(props.UPTIME||"0",10)),d=Math.floor(sec/86400),h=Math.floor(sec%86400/3600),m=Math.floor(sec%3600/60);
    const uptime=(d?d+"d ":"")+h+"h "+m+"m";put("runtime-uptime",uptime);
    const selinuxValue=String(props.SELINUX||"Unknown").trim();
    const permissive=/^permissive$/i.test(selinuxValue);
    const deviceSelinux=document.getElementById("overview-selinux"),configSelinux=document.getElementById("status-selinux");
    [deviceSelinux,configSelinux].forEach(el=>{if(!el)return;el.classList.toggle("is-selinux-warning",permissive);el.textContent=permissive?"Permissive — Please change your ROM":selinuxValue||"Unknown"});
  }catch(e){console.warn("System information query failed",e)}
  const jobs=[
    (async()=>{try{const r=await runShell("if command -v magisk >/dev/null 2>&1; then echo Magisk; elif [ -d /data/adb/ksu ] || command -v ksud >/dev/null 2>&1; then echo KernelSU; elif [ -d /data/adb/ap ] || command -v apd >/dev/null 2>&1; then echo APatch; else echo Unknown; fi");const e=document.getElementById("overview-root");if(e)e.textContent=r.trim()||"Unknown"}catch{const e=document.getElementById("overview-root");if(e)e.textContent="Unavailable"}})(),
    overviewTrackApps(),overviewDetectWebView(),overviewLoadModules(),overviewCountUserApps()
  ];
  await Promise.all(jobs);
  const config=`B=${BOXBRAIN}; M=/data/adb/modules/integrity-box; printf 'LINEAGE='; if getprop ro.lineage.version | grep -qi lineage || getprop ro.build.display.id | grep -qi lineage || getprop ro.build.version.incremental | grep -qi lineage; then echo Detected; else echo Spoofed; fi; printf 'PIXEL='; [ -f "$M/config.meow" ] && awk -F= '/^MODEL=/{print $2;exit}' "$M/config.meow" || echo None; printf 'TARGET='; [ -f /data/adb/tricky_store/target.txt ] && awk 'NF{n++} END{print n+0}' /data/adb/tricky_store/target.txt || echo 0; printf 'APPS='; [ -f "$M/apps.txt" ] && awk 'NF{n++} END{print n+0}' "$M/apps.txt" || echo 0; printf 'ZYGOTE='; [ -e "$M/stop" ] && echo Disabled || echo Enabled; printf 'ZYGISKLESS='; [ -d "$M/zygisk" ] && echo Disabled || echo Enabled; printf 'BLACKLIST='; [ -f "$B/blacklist.txt" ] && awk 'NF{n++} END{print n+0}' "$B/blacklist.txt" || echo 0; printf 'ADVANCED='; [ -e "$B/PIF/advanced" ] && echo Enabled || echo Disabled; printf 'ROM='; if [ -e "$B/disablevending" ] && [ -e "$B/disablegms" ]; then echo Disabled; elif [ -e "$B/disablevending" ] || [ -e "$B/disablegms" ]; then echo 'Partially disabled'; else echo 'Not configured'; fi; printf 'HASH='; [ -s "$B/hash.txt" ] && echo Configured || echo Disabled; printf 'SELINUX='; getenforce 2>/dev/null || echo Unknown; printf 'EXPIRY='; grep -i 'Estimated Expiry' "$M/config.meow" 2>/dev/null | head -n1 | cut -d':' -f2-`;
  try{
    const c={};(await runShell(config)).split(/\r?\n/).forEach(line=>{const i=line.indexOf("=");if(i>0)c[line.slice(0,i)]=line.slice(i+1).trim()});
    const map={LINEAGE:"LineageProp",PIXEL:"pixel",TARGET:"target",APPS:"apps",ZYGOTE:"zygote",ZYGISKLESS:"zygiskless",BLACKLIST:"blacklist",ADVANCED:"advanced",ROM:"rom-spoofing",HASH:"boot-hash",SELINUX:"selinux"};
    Object.entries(map).forEach(([k,id])=>setStatus(id,c[k]||"Unknown"));
    setStatus("patch",props["ro.build.version.security_patch"]||"Unknown");
    const exp=c.EXPIRY||"";
    if(exp){const dt=new Date(exp.replace(/[^0-9-]/g,"")+"T00:00:00");setStatus("expiry",isNaN(dt.getTime())?"Unknown":Math.max(0,Math.floor((dt-new Date())/86400000))+" days")}else setStatus("expiry","Unknown");
    const statusSelinux=document.getElementById("status-selinux");
    const permissive=/^permissive$/i.test(c.SELINUX||"");
    if(statusSelinux){statusSelinux.classList.toggle("is-selinux-warning",permissive);statusSelinux.textContent=permissive?"Permissive — Please change your ROM":(c.SELINUX||"Unknown")}
  }catch(e){console.warn("Integrity Box configuration query failed",e)}
  if(stamp)stamp.textContent="Updated "+new Date().toLocaleTimeString();
  window.__ibOverviewLoaded=true;
  window.__ibOverviewLastRun=Date.now();
  }finally{
    window.__ibOverviewBusy=false;
    if(refresh)refresh.disabled=false;
  }
}
function attachButtonListeners(){document.querySelectorAll(".list-row:not(.static)").forEach(btn=>{if(btn._attached)return;btn._attached=true;btn.addEventListener("click",async()=>{const script=btn.dataset.script,type=btn.dataset.type;btn.style.pointerEvents="none";btn.style.opacity=".5";try{const iframeTypes=["scanner","hash","user","flags","cache","nuke","piffork","propspoofer","pif","vending","downloader","support","report","spoofing","status","tee","xml","addon","conflict","pixel","hide","patch","source","ctrl"];if(iframeTypes.includes(type)){const pathMap={ctrl:"./Control/integritybox.html",hash:"./BootHash/integritybox.html",flags:"./Flags/integritybox.html",piffork:"./PlayIntegrityBox/integritybox.html",propspoofer:"./PropSpoofer/integritybox.html",vending:"./Certified/integritybox.html",support:"./Support/integritybox.html",report:"./Report/integritybox.html",user:"./TrickyStore/integritybox.html",xml:"./KeyboxLoader/integritybox.html",addon:"./Addon/integritybox.html",conflict:"./RootImplementation/integritybox.html",source:"./KeyboxSource/integritybox.html",pixel:"./Pixel/integritybox.html",hide:"./HideMyFiles/integritybox.html",spoofing:"./Spoofing/integritybox.html",downloader:"./Downloader/integritybox.html",tee:"./TEEsimulator/index.html"};const msg=messageMap[(type||script||"").replace(/\.sh$/i,"")];if(openingToastsEnabled)popup(msg?.start||"Opening...",msg?.type||"info");return openIframe(pathMap[type],{external:type==="support"})}if(script){if(messageMap[script]?.start)popup(messageMap[script].start,messageMap[script].type);await runShell(`sh ${MODDIR}/${script}`);if(messageMap[script]?.success)popup(messageMap[script].success,messageMap[script].type)}}catch(e){popup("Error: "+e.message,"error")}finally{btn.style.pointerEvents="";btn.style.opacity="";setTimeout(()=>{if(document.getElementById("home-view-overview")?.classList.contains("active"))updateDashboard(true)},500)}})})}
function activateHomeSubtab(key){
  const safe=key||"status";
  document.querySelectorAll(".home-subtab").forEach(b=>b.classList.toggle("active",b.dataset.subtab===safe));
  document.querySelectorAll(".home-view").forEach(v=>v.classList.toggle("active",v.id==="home-view-"+safe));
  if(safe==="logs")loadLogFiles();
  if(safe==="announcements")loadAnnouncements();
  if(safe==="status")refreshKeyboxStatus();
  if(safe==="overview")requestAnimationFrame(()=>updateDashboard());
}
function initHomeSubtabs(){
  document.querySelectorAll(".home-subtab").forEach(btn=>{
    if(btn._homeSubtabAttached)return;
    btn._homeSubtabAttached=true;
    btn.addEventListener("click",()=>{
      const key=btn.dataset.subtab;
      if(key==="support"){
        activateHomeSubtab("status");
        openIframe("https://MeowDump.github.io",{external:true,fromSupportTab:true});
        return;
      }
      activateHomeSubtab(key);
    });
  });
}
function escapeHtml(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function getMarkdownParser(){
  const m=window.marked;
  if(!m)return null;
  if(typeof m.parse==="function")return m;
  if(m.marked&&typeof m.marked.parse==="function")return m.marked;
  return null;
}
function markdownToHtml(md){
  const parser=getMarkdownParser();
  if(!parser){
    console.error("Markdown renderer unavailable");
    return `<p>${escapeHtml(md).replace(/\n/g,"<br>")}</p>`;
  }
  try{
    const renderer=new parser.Renderer();
    renderer.html=token=>escapeHtml(typeof token==="string"?token:token?.text||"");
    return parser.parse(String(md||""),{gfm:true,breaks:false,mangle:false,headerIds:false,renderer});
  }catch(e){
    console.error("Markdown rendering failed",e);
    return `<p>${escapeHtml(md).replace(/\n/g,"<br>")}</p>`;
  }
}
function openAnnouncementUrl(url){
  try{
    const u=new URL(url,location.href);
    if(!/^https?:$/i.test(u.protocol))return;
    const safe=u.href;
    runShell(`am start -a android.intent.action.VIEW -d ${shellQuote(safe)}`).catch(()=>{
      try{window.open(safe,"_blank","noopener,noreferrer")}catch{}
    });
  }catch(e){console.error("Invalid announcement URL",e)}
}
function bindAnnouncementLinks(out){
  out.querySelectorAll("a[href]").forEach(a=>{
    a.style.pointerEvents="auto";
    a.setAttribute("target","_blank");
    a.setAttribute("rel","noopener noreferrer");
    a.addEventListener("click",e=>{
      e.preventDefault();
      e.stopPropagation();
      openAnnouncementUrl(a.getAttribute("href"));
    });
  });
}
function bindAnnouncementImages(out){
  out.querySelectorAll("img[src]").forEach(img=>{
    let url;
    try{url=new URL(img.getAttribute("src"),ANNOUNCEMENT_URL);if(!/^https?:$/.test(url.protocol))throw new Error("Unsupported image URL")}catch{img.remove();return}
    img.src=url.href;
    img.loading="lazy";
    img.decoding="async";
    img.classList.add("announcement-inline-image");
    img.tabIndex=0;
    img.setAttribute("role","button");
    img.setAttribute("aria-label",img.alt||"Open announcement image");
    const open=()=>openAnnouncementImage(url.href,img.alt||"");
    img.addEventListener("click",open);
    img.addEventListener("keydown",e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();open()}});
  });
}
let announcementImageScale=1;
function openAnnouncementImage(src,caption){
  const overlay=document.getElementById("announcement-image-overlay"),img=document.getElementById("announcement-image-full"),label=document.getElementById("announcement-image-caption");
  if(!overlay||!img)return;
  img.src=src;img.alt=caption||"Announcement image";if(label)label.textContent=caption||"Announcement image";
  announcementImageScale=1;updateAnnouncementImageScale();overlay.hidden=false;document.body.classList.add("announcement-image-open");
}
function updateAnnouncementImageScale(){
  const img=document.getElementById("announcement-image-full"),reset=document.getElementById("announcement-image-zoom-reset");
  if(img)img.style.transform=`scale(${announcementImageScale})`;
  if(reset)reset.textContent=`${Math.round(announcementImageScale*100)}%`;
}
function initAnnouncementImageViewer(){
  const overlay=document.getElementById("announcement-image-overlay"),stage=document.getElementById("announcement-image-stage");
  const close=()=>{if(!overlay)return;overlay.hidden=true;document.body.classList.remove("announcement-image-open");const img=document.getElementById("announcement-image-full");if(img)img.removeAttribute("src")};
  document.getElementById("announcement-image-close")?.addEventListener("click",close);
  overlay?.addEventListener("click",e=>{if(e.target===overlay)close()});
  document.getElementById("announcement-image-zoom-in")?.addEventListener("click",()=>{announcementImageScale=Math.min(4,+(announcementImageScale+.25).toFixed(2));updateAnnouncementImageScale()});
  document.getElementById("announcement-image-zoom-out")?.addEventListener("click",()=>{announcementImageScale=Math.max(.5,+(announcementImageScale-.25).toFixed(2));updateAnnouncementImageScale()});
  document.getElementById("announcement-image-zoom-reset")?.addEventListener("click",()=>{announcementImageScale=1;updateAnnouncementImageScale()});
  document.addEventListener("keydown",e=>{if(e.key==="Escape"&&overlay&&!overlay.hidden)close()});
  let touchDistance=0,touchScale=1;
  stage?.addEventListener("touchstart",e=>{if(e.touches.length===2){touchDistance=Math.hypot(e.touches[0].clientX-e.touches[1].clientX,e.touches[0].clientY-e.touches[1].clientY);touchScale=announcementImageScale}},{passive:true});
  stage?.addEventListener("touchmove",e=>{if(e.touches.length===2&&touchDistance>0){e.preventDefault();const d=Math.hypot(e.touches[0].clientX-e.touches[1].clientX,e.touches[0].clientY-e.touches[1].clientY);announcementImageScale=Math.min(4,Math.max(.5,touchScale*d/touchDistance));updateAnnouncementImageScale()}},{passive:false});
  stage?.addEventListener("touchend",()=>{touchDistance=0},{passive:true});
}
let announcementCache="";
async function loadAnnouncements(force=false){
  const out=document.getElementById("announcement-output");
  if(!out)return;
  if(announcementCache&&!force){out.innerHTML=markdownToHtml(announcementCache);bindAnnouncementLinks(out);bindAnnouncementImages(out);return}
  out.innerHTML='<div class="empty-state">Loading announcements...</div>';
  try{
    const r=await fetch(ANNOUNCEMENT_URL,{cache:force?"no-store":"default"});
    if(!r.ok)throw Error("HTTP "+r.status);
    announcementCache=await r.text();
    out.innerHTML=markdownToHtml(announcementCache);
    bindAnnouncementLinks(out);
    bindAnnouncementImages(out);
  }catch(e){out.innerHTML='<div class="empty-state">Unable to load announcements. Check your connection and try again.</div>'}
}
function shellQuote(value){return "'"+String(value).replace(/'/g,"'\\''")+"'"}
function parseTimestamp(line){
  const text=String(line||"");
  const months={jan:0,january:0,feb:1,february:1,mar:2,march:2,apr:3,april:3,may:4,jun:5,june:5,jul:6,july:6,aug:7,august:7,sep:8,sept:8,september:8,oct:9,october:9,nov:10,november:10,dec:11,december:11};
  let m=text.match(/\b(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?/);
  if(m){
    const d=new Date(Number(m[1]),Number(m[2])-1,Number(m[3]),Number(m[4]),Number(m[5]),Number(m[6]||0),Number((m[7]||"").slice(0,3).padEnd(3,"0")||0));
    if(!Number.isNaN(d.getTime()))return {date:d,key:d.getTime(),text:m[0]};
  }
  m=text.match(/\b(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?/);
  if(m){
    const d=new Date(Number(m[3]),Number(m[2])-1,Number(m[1]),Number(m[4]),Number(m[5]),Number(m[6]||0),Number((m[7]||"").slice(0,3).padEnd(3,"0")||0));
    if(!Number.isNaN(d.getTime()))return {date:d,key:d.getTime(),text:m[0]};
  }
  m=text.match(/\b([A-Za-z]{3,9})[ ._-]+(\d{1,2})(?:,?[ ._-]+(\d{4}))?[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([AP]M))?/i);
  if(m&&months[m[1].toLowerCase()]!==undefined){
    let year=m[3]?Number(m[3]):new Date().getFullYear(), hour=Number(m[4]);
    const ap=(m[7]||"").toUpperCase(); if(ap==="PM"&&hour<12)hour+=12; if(ap==="AM"&&hour===12)hour=0;
    const d=new Date(year,months[m[1].toLowerCase()],Number(m[2]),hour,Number(m[5]),Number(m[6]||0));
    if(!Number.isNaN(d.getTime()))return {date:d,key:d.getTime(),text:m[0]};
  }
  return null;
}
function lineHtml(line){
  const ts=parseTimestamp(line);
  const escaped=escapeHtml(line);
  if(!ts)return `<div class="log-line"><span class="log-line-text">${escaped}</span></div>`;
  const prefix=escapeHtml(ts.text);
  const rest=escaped.replace(prefix,"");
  let cls="";
  if(/\b(error|failed|failure|fatal|denied|exception)\b/i.test(line))cls=" log-severity-error";
  else if(/\b(warn|warning)\b/i.test(line))cls=" log-severity-warn";
  else if(/\b(success|passed|ok|done)\b/i.test(line))cls=" log-severity-success";
  return `<div class="log-line${cls}"><time class="log-time">${prefix}</time><span class="log-line-text">${rest}</span></div>`;
}
function renderLogFileList(files,selected){
  const list=document.getElementById("log-files");
  if(!list)return;
  if(!files.length){list.innerHTML='<div class="empty-state">No readable log files found.</div>';return;}
  list.innerHTML=files.map(name=>{
    const active=name===selected?' active':'';
    return `<button type="button" class="log-file${active}" data-log-file="${escapeHtml(name)}" title="Open ${escapeHtml(name)}"><span class="log-file-name">${escapeHtml(name)}</span><span class="log-file-arrow">›</span></button>`;
  }).join('');
  list.querySelectorAll('.log-file').forEach(btn=>btn.addEventListener('click',()=>openLogFile(btn.dataset.logFile)));
}
async function listLogFiles(){
  const raw=await runShell(`
    dir=${shellQuote(LOGDIR)}
    if [ ! -e "$dir" ]; then echo __IB_MISSING__
    elif [ ! -d "$dir" ]; then echo __IB_NOT_DIRECTORY__
    elif [ ! -r "$dir" ] || [ ! -x "$dir" ]; then echo __IB_DENIED__
    else
      find "$dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null
    fi
  `);
  const lines=String(raw||'').split(/\r?\n/).map(x=>x.trim()).filter(Boolean);
  if(lines.includes('__IB_MISSING__'))throw new Error(`Log directory does not exist: ${LOGDIR}`);
  if(lines.includes('__IB_NOT_DIRECTORY__'))throw new Error(`Log path is not a directory: ${LOGDIR}`);
  if(lines.includes('__IB_DENIED__'))throw new Error(`Permission denied while accessing: ${LOGDIR}`);
  return [...new Set(lines.filter(x=>!x.startsWith('__IB_')&&!/^\./.test(x)))].sort((a,b)=>a.localeCompare(b));
}
let currentLogText = "";
async function openLogFile(file){
  const output=document.getElementById('log-output'),meta=document.getElementById('log-meta'),title=document.getElementById('log-viewer-title'),copy=document.getElementById('log-copy');
  if(!output||!file)return;
  selectedLog=file;
  document.querySelectorAll('.log-file').forEach(btn=>btn.classList.toggle('active',btn.dataset.logFile===file));
  output.innerHTML='<div class="empty-state">Reading log…</div>';
  if(title)title.textContent=file;
  if(meta)meta.textContent='Reading…';
  if(copy){copy.disabled=true;copy.textContent='Copy'}
  currentLogText="";
  try{
    const path=`${LOGDIR}/${file}`;
    const raw=await runShell(`if [ ! -e ${shellQuote(path)} ]; then echo __IB_MISSING__; elif [ ! -f ${shellQuote(path)} ]; then echo __IB_NOT_FILE__; elif [ ! -r ${shellQuote(path)} ]; then echo __IB_DENIED__; else cat ${shellQuote(path)} 2>/dev/null; fi`);
    const rawText=String(raw||'').replace(/\r/g,'');
    if(rawText.trim()==='__IB_MISSING__')throw new Error('The selected log file no longer exists.');
    if(rawText.trim()==='__IB_NOT_FILE__')throw new Error('The selected path is not a regular log file.');
    if(rawText.trim()==='__IB_DENIED__')throw new Error('Permission denied while reading the selected log file.');
    currentLogText=rawText;
    if(!rawText){
      output.innerHTML='<div class="empty-state">This log file is empty.</div>';
      if(meta)meta.textContent='Empty file';
    }else{
      const lines=rawText.replace(/\n$/,'').split('\n');
      output.innerHTML=lines.map(lineHtml).join('');
      if(meta)meta.textContent=`Complete file • ${lines.length} line${lines.length===1?'':'s'}`;
      if(copy)copy.disabled=false;
    }
  }catch(e){
    output.innerHTML=`<div class="empty-state log-error"><strong>Unable to open log</strong><span>${escapeHtml(e?.message||String(e))}</span></div>`;
    if(meta)meta.textContent='Read failed';
  }
}
function initLogCopy(){
  const copy=document.getElementById('log-copy');
  if(!copy)return;
  copy.addEventListener('click',async()=>{
    if(!currentLogText)return;
    try{
      if(navigator.clipboard?.writeText){await navigator.clipboard.writeText(currentLogText);}
      else{const ta=document.createElement('textarea');ta.value=currentLogText;ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();document.execCommand('copy');ta.remove();}
      copy.textContent='Copied';
      popup('Log copied to clipboard','success');
      setTimeout(()=>{if(copy)copy.textContent='Copy'},1400);
    }catch{popup('Unable to copy log','error')}
  });
}
function initLogFileToggle(){
  const section=document.getElementById('logs-file-section'),toggle=document.getElementById('logs-file-toggle');
  if(!section||!toggle)return;
  toggle.addEventListener('click',()=>{
    const collapsed=section.classList.toggle('collapsed');
    toggle.setAttribute('aria-expanded',String(!collapsed));
  });
}
function initLogRefresh(){
  document.getElementById('refresh-logs')?.addEventListener('click',()=>loadLogFiles());
}
async function loadLogFiles(){
  const list=document.getElementById('log-files'),output=document.getElementById('log-output'),meta=document.getElementById('log-meta'),title=document.getElementById('log-viewer-title');
  if(!list)return;
  list.innerHTML='<div class="empty-state">Scanning available logs…</div>';
  if(output)output.innerHTML='<div class="empty-state">Select a file above.</div>';
  if(meta)meta.textContent='Scanning…';
  if(title)title.textContent='Select a log file';
  try{
    const files=await listLogFiles();
    const preferred=selectedLog&&files.includes(selectedLog)?selectedLog:null;
    renderLogFileList(files,preferred);
    if(!files.length){if(meta)meta.textContent='No files';return;}
    if(preferred)await openLogFile(preferred);
    else if(meta)meta.textContent=`${files.length} file${files.length===1?'':'s'} available`;
  }catch(e){
    list.innerHTML=`<div class="empty-state log-error"><strong>Log scan failed</strong><span>${escapeHtml(e?.message||String(e))}</span></div>`;
    if(meta)meta.textContent='Scan failed';
  }
}
function applyLanguageDirection(lang){
  const rtl=['ar','fa','he','ur'].includes(String(lang||'').toLowerCase());
  document.documentElement.dir=rtl?'rtl':'ltr';
  document.body.dir=rtl?'rtl':'ltr';
  document.documentElement.classList.toggle('rtl',rtl);
  document.documentElement.classList.toggle('ltr',!rtl);
}
let languageSelectorDelegationBound=false;
let languagePickerOverlay=null;
function closeLanguagePicker(){
  if(!languagePickerOverlay)return;
  languagePickerOverlay.classList.remove('is-open');
  languagePickerOverlay.setAttribute('aria-hidden','true');
  document.body.classList.remove('language-picker-open');
}
function openLanguagePicker(source){
  const select=source?.querySelector?.('.lang-dropdown-inline')||document.querySelector('.lang-dropdown-inline');
  if(!select||!languagePickerOverlay)return;
  const list=languagePickerOverlay.querySelector('.language-picker-options');
  const activeLang=String(window.__ibI18nState?.lang||localStorage.getItem('ibLang')||uiSettings.lang||select.value||'en');
  list.replaceChildren();
  [...select.options].forEach(option=>{
    const button=document.createElement('button');
    button.type='button'; button.className='language-picker-option';
    button.textContent=option.textContent.trim(); button.dataset.value=option.value;
    button.setAttribute('aria-selected',String(option.value===activeLang));
    if(option.value===activeLang)button.classList.add('is-selected');
    button.addEventListener('click',()=>{
      const selects=[...document.querySelectorAll('.lang-dropdown-inline')];
      selects.forEach(item=>{item.value=option.value});
      const primary=selects[0];
      if(primary)primary.dispatchEvent(new Event('change',{bubbles:true}));
      closeLanguagePicker();
    });
    list.appendChild(button);
  });
  languagePickerOverlay.classList.add('is-open');
  languagePickerOverlay.setAttribute('aria-hidden','false');
  document.body.classList.add('language-picker-open');
}
function ensureLanguagePicker(){
  if(languagePickerOverlay)return;
  languagePickerOverlay=document.createElement('div');
  languagePickerOverlay.id='language-picker-overlay';
  languagePickerOverlay.className='language-picker-overlay';
  languagePickerOverlay.setAttribute('aria-hidden','true');
  languagePickerOverlay.innerHTML='<section class="language-picker-panel" role="dialog" aria-modal="true" aria-label="Select language"><header class="language-picker-header"><button type="button" class="language-picker-back" aria-label="Back">‹</button><div><div class="language-picker-heading">Select language</div><div class="language-picker-caption">Choose your preferred language</div></div></header><div class="language-picker-options"></div></section>';
  document.body.appendChild(languagePickerOverlay);
  languagePickerOverlay.querySelector('.language-picker-back').addEventListener('click',closeLanguagePicker);
  languagePickerOverlay.addEventListener('click',event=>{if(event.target===languagePickerOverlay)closeLanguagePicker()});
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&languagePickerOverlay?.classList.contains('is-open'))closeLanguagePicker()});
}
function initLanguageSelector(){
  const selects=document.querySelectorAll('.lang-dropdown-inline');
  if(!selects.length)return;
  selects.forEach(select=>{select.value=uiSettings.lang||'en';select.setAttribute('aria-hidden','true');select.tabIndex=-1});
  applyLanguageDirection(uiSettings.lang||'en');
  ensureLanguagePicker();
  if(languageSelectorDelegationBound)return;
  languageSelectorDelegationBound=true;
  document.addEventListener('click',event=>{
    const row=event.target.closest('.language-setting-row');
    if(!row)return;
    if(event.target.closest('.lang-dropdown-inline'))event.preventDefault();
    openLanguagePicker(row);
  });
  document.addEventListener('change',async event=>{
    const select=event.target.closest('.lang-dropdown-inline');
    if(!select)return;
    const lang=select.value||'en';
    document.querySelectorAll('.lang-dropdown-inline').forEach(item=>{item.value=lang});
    try{if(window.i18nSetLanguage)await window.i18nSetLanguage(lang);else if(lang==='en')location.reload()}catch{}
    uiSettings.lang=lang;
    await persistUISettings();
    applyLanguageDirection(lang);
    broadcastLangChange(lang);
  });
}

const BACKGROUND_MUSIC_URL="https://raw.githubusercontent.com/MeowBlog/Articles/refs/heads/main/music.mp3";
const MUSIC_DB_NAME="integrity-box-media-cache",MUSIC_DB_STORE="assets",MUSIC_CACHE_KEY="background-music-v1";
let backgroundMusicElement=null,backgroundMusicObjectUrl="",musicRetryBound=false,musicLoadPromise=null;
function openMusicDB(){return new Promise((resolve,reject)=>{if(!("indexedDB" in window))return reject(new Error("Offline cache unavailable"));const request=indexedDB.open(MUSIC_DB_NAME,1);request.onupgradeneeded=()=>{const db=request.result;if(!db.objectStoreNames.contains(MUSIC_DB_STORE))db.createObjectStore(MUSIC_DB_STORE)};request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error||new Error("Cache open failed"))})}
async function readCachedMusic(){const db=await openMusicDB();return new Promise((resolve,reject)=>{const tx=db.transaction(MUSIC_DB_STORE,"readonly"),req=tx.objectStore(MUSIC_DB_STORE).get(MUSIC_CACHE_KEY);req.onsuccess=()=>{db.close();resolve(req.result instanceof Blob?req.result:null)};req.onerror=()=>{db.close();reject(req.error)}})}
async function writeCachedMusic(blob){try{const db=await openMusicDB();await new Promise((resolve,reject)=>{const tx=db.transaction(MUSIC_DB_STORE,"readwrite");tx.objectStore(MUSIC_DB_STORE).put(blob,MUSIC_CACHE_KEY);tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error)});db.close();return true}catch{return false}}
async function resolveMusicSource(){
  if(backgroundMusicObjectUrl)return backgroundMusicObjectUrl;
  if(musicLoadPromise)return musicLoadPromise;
  musicLoadPromise=(async()=>{
    try{const cached=await readCachedMusic();if(cached&&cached.size>0){backgroundMusicObjectUrl=URL.createObjectURL(cached);return backgroundMusicObjectUrl}}catch{}
    const response=await fetch(BACKGROUND_MUSIC_URL,{mode:"cors",cache:"force-cache",credentials:"omit"});
    if(!response.ok)throw new Error(`Music download failed (${response.status})`);
    const blob=await response.blob();if(!blob.size)throw new Error("Downloaded music is empty");
    await writeCachedMusic(blob);
    backgroundMusicObjectUrl=URL.createObjectURL(blob);
    return backgroundMusicObjectUrl;
  })().finally(()=>{musicLoadPromise=null});
  return musicLoadPromise;
}
function getBackgroundMusic(){if(!backgroundMusicElement){backgroundMusicElement=new Audio();backgroundMusicElement.loop=true;backgroundMusicElement.preload="auto";backgroundMusicElement.volume=.35}return backgroundMusicElement}
async function startBackgroundMusic(){
  if(!uiSettings.backgroundMusic)return false;
  try{
    const audio=getBackgroundMusic();
    if(!audio.src){audio.src=await resolveMusicSource();audio.load()}
    if(!uiSettings.backgroundMusic)return false;
    await audio.play();
    if(musicRetryBound){document.removeEventListener("pointerdown",retryBackgroundMusic,true);document.removeEventListener("keydown",retryBackgroundMusic,true);musicRetryBound=false}
    return true;
  }catch(e){
    if(!musicRetryBound){document.addEventListener("pointerdown",retryBackgroundMusic,true);document.addEventListener("keydown",retryBackgroundMusic,true);musicRetryBound=true}
    if(!navigator.onLine){popup("Music is not cached yet. Connect once to save it for offline playback.","warn")}
    return false;
  }
}
async function retryBackgroundMusic(){if(!uiSettings.backgroundMusic)return;await startBackgroundMusic()}
function stopBackgroundMusic(){if(backgroundMusicElement){backgroundMusicElement.pause();backgroundMusicElement.currentTime=0}if(musicRetryBound){document.removeEventListener("pointerdown",retryBackgroundMusic,true);document.removeEventListener("keydown",retryBackgroundMusic,true);musicRetryBound=false}}

const KSUN_FLAG = `${BOXBRAIN}/ksu_next`;
const KSUN_LEGACY_FLAG = `${BOXBRAIN}/ksun`;
const FALSE_DETECTION_SCRIPT = `${MODDIR}/hehe.sh`;
const KSUN_FLAG_CHECK = `[ -e ${shellQuote(KSUN_FLAG)} ] || [ -e ${shellQuote(KSUN_LEGACY_FLAG)} ]`;
async function getKsuNextFlagStatus(){
  try{
    return (await runShell(`if [ -e ${shellQuote(KSUN_FLAG)} ]; then echo ksu_next; elif [ -e ${shellQuote(KSUN_LEGACY_FLAG)} ]; then echo ksun; else echo absent; fi`)).trim() || "absent";
  }catch(e){console.warn("KSU Next flag detection failed:",e.message);return "error"}
}
async function isKsuNextDetected(){return ["ksu_next","ksun"].includes(await getKsuNextFlagStatus())}
async function runKsuNextCompatibility(){
  if(window.__ibKsuNextCompatibilityAttempted)return;
  window.__ibKsuNextCompatibilityAttempted=true;
  try{
    await runShell(`if { ${KSUN_FLAG_CHECK}; } && [ -f ${shellQuote(FALSE_DETECTION_SCRIPT)} ]; then sh ${shellQuote(FALSE_DETECTION_SCRIPT)}; fi`);
  }catch(e){console.warn("KSU Next compatibility check failed:",e.message)}
}
async function updateKsuNextStatus(){
  const status=document.getElementById("ksu-next-status"),badge=document.getElementById("ksu-next-badge");
  const flagStatus=await getKsuNextFlagStatus();
  const detected=flagStatus==="ksu_next"||flagStatus==="ksun";
  if(status)status.textContent=flagStatus==="ksu_next"?"/data/adb/Box-Brain/ksu_next detected":flagStatus==="ksun"?"Optimisation started in background":flagStatus==="error"?"Unable to read flag status (KSU API unavailable)":"Module is already optimised";
  if(badge){badge.textContent=flagStatus==="ksu_next"?"Detected":flagStatus==="ksun"?"Completed":flagStatus==="error"?"Unavailable":"Optimised";badge.classList.toggle("is-active",detected);badge.classList.toggle("is-inactive",!detected)}
}

function initInterfaceSettings(){
  const edgeSwipe=document.getElementById("toggle-edge-swipe"),edgeTap=document.getElementById("toggle-edge-tap"),backButton=document.getElementById("toggle-back-button"),tabSwipe=document.getElementById("toggle-tab-swipe"),fullscreen=document.getElementById("toggle-fullscreen"),toasts=document.getElementById("toggle-opening-toasts"),skipIntro=document.getElementById("toggle-skip-intro"),left=document.getElementById("gesture-left"),right=document.getElementById("gesture-right"),music=document.getElementById("toggle-background-music");
  if(music){music.checked=uiSettings.backgroundMusic;music.addEventListener("change",async()=>{await setUISetting("backgroundMusic",music.checked);if(music.checked){const started=await startBackgroundMusic();if(!started)popup("Music is enabled; tap the page once if playback is blocked","info")}else stopBackgroundMusic()})}
  if(uiSettings.backgroundMusic)startBackgroundMusic();
  if(fullscreen){fullscreen.checked=uiSettings.fullscreen;if(uiSettings.fullscreen)setTimeout(()=>setFullScreen(true),120);fullscreen.addEventListener("change",()=>setFullScreen(fullscreen.checked))}
  if(toasts){openingToastsEnabled=uiSettings.openingToasts;toasts.checked=openingToastsEnabled;toasts.addEventListener("change",()=>{openingToastsEnabled=toasts.checked;setUISetting("openingToasts",openingToastsEnabled)})}
  if(skipIntro){skipIntro.checked=uiSettings.skipIntro;skipIntro.addEventListener("change",()=>{const on=skipIntro.checked;document.documentElement.classList.toggle("skip-intro",on);setUISetting("skipIntro",on);if(on)document.getElementById("intro-overlay")?.remove()})}
  if(edgeSwipe){edgeSwipe.checked=uiSettings.edgeSwipe;edgeTap.checked=uiSettings.edgeTap;backButton.checked=uiSettings.backButton;tabSwipe.checked=uiSettings.tabSwipe;updateSideButtons(uiSettings.gestureRight);edgeSwipe.addEventListener("change",async()=>{uiSettings.edgeSwipe=edgeSwipe.checked;await persistUISettings();popup(edgeSwipe.checked?"Edge swipe enabled":"Edge swipe disabled")});edgeTap.addEventListener("change",async()=>{uiSettings.edgeTap=edgeTap.checked;await persistUISettings();popup(edgeTap.checked?"Edge tap enabled":"Edge tap disabled")});backButton.addEventListener("change",async()=>{uiSettings.backButton=backButton.checked;await persistUISettings();popup(backButton.checked?"Floating back button enabled":"Floating back button disabled")});tabSwipe.addEventListener("change",async()=>{uiSettings.tabSwipe=tabSwipe.checked;await persistUISettings();popup(tabSwipe.checked?"Tab swipe enabled":"Tab swipe disabled")});left.onclick=()=>setGestureSide(false);right.onclick=()=>setGestureSide(true)}}
function updateSideButtons(isRight){document.getElementById("gesture-left")?.classList.toggle("active",!isRight);document.getElementById("gesture-right")?.classList.toggle("active",isRight);const l=document.getElementById("gesture-side-label");if(l)l.textContent=isRight?"Right edge":"Left edge"}
async function setGestureSide(isRight){uiSettings.gestureRight=!!isRight;await persistUISettings();updateSideButtons(isRight);popup(isRight?"Back gesture: right edge":"Back gesture: left edge")}

const minimalActionSectionPositions = [];
let minimalActionLauncher = null;
function applyMinimalTileDescriptions(hidden){
  document.documentElement.classList.toggle("minimal-hide-descriptions",!!hidden);
  try{localStorage.setItem("ibMinimalHideTileDescriptions",hidden?"1":"0")}catch{}
  const toggle=document.getElementById("minimal-description-toggle");
  if(toggle)toggle.checked=!!hidden;
}
function applyMinimalSimplicity(enabled){
  const requested=!!enabled;
  try{localStorage.setItem("ibMinimalSimplicityMode",requested?"1":"0")}catch{}
  const active=requested&&document.documentElement.classList.contains("ui-studio");
  document.documentElement.classList.toggle("minimal-simplicity",active);
  const launcher=document.getElementById("minimal-action-launcher");
  const hideByType=new Map([
    ["repair",["repair mode"]],
    ["addon",["customize scope"]],
    ["conflict",["conflict resolver"]],
    ["report",["report a problem"]],
    ["support",["webui translation team"]]
  ]);
  if(launcher){
    launcher.querySelectorAll(".minimal-launcher-section").forEach(section=>{
      const list=section.querySelector(".list:not(.settings-list)");
      if(!list)return;
      const tiles=Array.from(list.querySelectorAll(":scope > .list-row:not(.static)"));
      tiles.forEach(tile=>{
        const title=(tile.querySelector(".row-title")?.textContent||"").replace(/\s+/g," ").trim().toLowerCase();
        const type=(tile.dataset.type||"").trim().toLowerCase();
        const titles=hideByType.get(type)||[];
        const hide=active&&(titles.includes(title)||titles.includes("*"));
        tile.classList.toggle("minimal-simplicity-hidden",hide);
        tile.setAttribute("aria-hidden",String(hide));
        if(hide)tile.style.setProperty("display","none","important");
        else tile.style.removeProperty("display");
        tile.style.removeProperty("grid-column");
        tile.style.removeProperty("width");
      });
      const visible=tiles.filter(tile=>!tile.classList.contains("minimal-simplicity-hidden"));
      list.classList.toggle("minimal-simplicity-odd",active&&visible.length%2===1);
      list.classList.toggle("minimal-simplicity-even",active&&visible.length%2===0);
      visible.forEach((tile,index)=>{
        tile.classList.toggle("minimal-simplicity-last-odd",active&&visible.length%2===1&&index===visible.length-1);
      });
      section.classList.toggle("minimal-simplicity-empty",active&&visible.length===0);
      const heading=section.querySelector(".section-title");
      if(heading)heading.setAttribute("aria-hidden",String(active&&visible.length===0));
    });
  }
  const toggle=document.getElementById("minimal-simplicity-toggle");
  if(toggle)toggle.checked=active;
}
function setMinimalSettingsCardsHidden(hidden){
  const launcher=document.getElementById("minimal-action-launcher");
  if(!launcher)return;
  launcher.querySelectorAll(".minimal-description-setting").forEach(setting=>{
    setting.hidden=!!hidden;
    setting.classList.toggle("hidden",!!hidden);
    if(hidden)setting.style.setProperty("display","none","important");
    else setting.style.removeProperty("display");
  });
}

function setMinimalAllActions(enabled){
  document.documentElement.classList.toggle("minimal-all-actions",enabled);
  const home=document.getElementById("home-view-status");
  if(!home)return;
  if(enabled){
    if(minimalActionLauncher)return;
    minimalActionLauncher=document.createElement("div");
    minimalActionLauncher.id="minimal-action-launcher";
    minimalActionLauncher.className="minimal-action-launcher";
    let hideDescriptions=false;
    try{hideDescriptions=localStorage.getItem("ibMinimalHideTileDescriptions")!=="0"}catch{hideDescriptions=true}
    let simplicityEnabled=false;
    try{simplicityEnabled=localStorage.getItem("ibMinimalSimplicityMode")==="1"}catch{simplicityEnabled=false}
    const simplicityControl=document.createElement("section");
    simplicityControl.className="minimal-description-setting minimal-simplicity-setting";
    simplicityControl.innerHTML='<div class="minimal-setting-copy"><strong>Simplicity Mode</strong><small>Show only essential features in Minimal UI.</small></div><label class="switch minimal-setting-switch"><input id="minimal-simplicity-toggle" type="checkbox" aria-label="Simplicity Mode"><span></span></label>';
    minimalActionLauncher.appendChild(simplicityControl);
    const simplicityToggle=simplicityControl.querySelector("input");
    simplicityToggle.checked=simplicityEnabled;
    simplicityToggle.addEventListener("change",()=>applyMinimalSimplicity(simplicityToggle.checked));
    const descriptionControl=document.createElement("section");
    descriptionControl.className="minimal-description-setting";
    descriptionControl.innerHTML='<div class="minimal-setting-copy"><strong>Hide Tile Description</strong><small>Hide the supporting text beneath each tile title.</small></div><label class="switch minimal-setting-switch"><input id="minimal-description-toggle" type="checkbox" aria-label="Hide tile descriptions"><span></span></label>';
    minimalActionLauncher.appendChild(descriptionControl);
    const descriptionToggle=descriptionControl.querySelector("input");
    descriptionToggle.checked=hideDescriptions;
    descriptionToggle.addEventListener("change",()=>applyMinimalTileDescriptions(descriptionToggle.checked));
    document.documentElement.classList.toggle("minimal-hide-descriptions",hideDescriptions);
    const languageSection=document.querySelector("#tab-more .language-setting-row")?.closest(".list-section");
    const sections=Array.from(document.querySelectorAll("#tab-home .list-section, #tab-tools .list-section, #tab-more .list-section"))
      .filter(section=>{
        if(section===languageSection)return false;
        const list=section.querySelector(".list:not(.settings-list)");
        return !!list && list.querySelectorAll(".list-row:not(.static)").length>0;
      });
    const ordered=sections.map((section,index)=>({
      section,
      index,
      count:section.querySelectorAll(".list:not(.settings-list) > .list-row:not(.static)").length
    })).sort((a,b)=>(a.count===1?1:0)-(b.count===1?1:0)||a.index-b.index);
    ordered.forEach(item=>{
      const clone=item.section.cloneNode(true);
      clone.classList.add("minimal-launcher-section");
      clone.dataset.originalSectionIndex=String(item.index);
      clone.classList.toggle("minimal-odd-actions",item.count%2===1);
      clone.querySelectorAll("[id]").forEach(el=>el.removeAttribute("id"));
      minimalActionLauncher.appendChild(clone);
    });
    if(languageSection){
      const languageClone=languageSection.cloneNode(true);
      languageClone.classList.add("minimal-language-section");
      languageClone.querySelectorAll("[id]").forEach(el=>el.removeAttribute("id"));
      minimalActionLauncher.appendChild(languageClone);
      const languageSelect=languageClone.querySelector(".lang-dropdown-inline");
      if(languageSelect)languageSelect.value=uiSettings.lang||'en';
    }
    home.appendChild(minimalActionLauncher);
    const integrityCard=document.getElementById("home-integrity-card");
    const settingsHidden=!!integrityCard?.classList.contains("collapsed");
    setMinimalSettingsCardsHidden(settingsHidden);
    applyMinimalSimplicity(simplicityEnabled);
    attachButtonListeners();
  }else if(minimalActionLauncher){
    minimalActionLauncher.remove();
    minimalActionLauncher=null;
  }
}

const CUSTOM_FONT_PATH="/data/adb/modules/integrity-box/webroot/custom.ttf";
function customFontUrl(){return new URL("./custom.ttf?ibfont="+Date.now(),window.location.href).href}
function applyCustomFont(enabled){
  const active=!!enabled;
  document.documentElement.classList.toggle("ib-custom-font-enabled",active);
  try{localStorage.setItem("ibCustomFontEnabled",active?"1":"0")}catch{}
  const url=customFontUrl();
  if(active){
    let fontStyle=document.getElementById("ib-custom-font-face");
    if(!fontStyle){fontStyle=document.createElement("style");fontStyle.id="ib-custom-font-face";document.head.appendChild(fontStyle)}
    fontStyle.textContent=`@font-face{font-family:IBCustomFont;src:url("${url}") format("truetype");font-style:normal;font-weight:100 900;font-display:swap}`;
    document.documentElement.classList.remove("ib-custom-font-ready");
    document.fonts?.load('16px "IBCustomFont"').then(()=>{
      document.documentElement.classList.add("ib-custom-font-ready");
      document.querySelectorAll("iframe").forEach(frame=>{try{frame.contentDocument?.fonts?.load('16px "IBCustomFont"')}catch{}});
    }).catch(()=>document.documentElement.classList.remove("ib-custom-font-ready"));
  }else document.documentElement.classList.remove("ib-custom-font-ready");
  const frameStyle=`@font-face{font-family:IBCustomFont;src:url("${url}") format("truetype");font-style:normal;font-weight:100 900;font-display:swap}html,body,body *:not(i):not(.material-icons):not(.material-icons-outlined):not(.material-icons-round):not(.material-icons-sharp):not(.material-symbols-outlined):not(.material-symbols-rounded):not(.material-symbols-sharp):not([class*="material-symbol"]):not([class*="material-icons"]):not(.home-brand):not(.brand-title):not(.brand-version){font-family:IBCustomFont,system-ui,sans-serif!important}`;
  document.querySelectorAll("iframe").forEach(frame=>{
    const inject=()=>{try{
      const doc=frame.contentDocument;if(!doc||!doc.documentElement)return;
      let style=doc.getElementById("ib-custom-font-frame-style");
      if(!style){style=doc.createElement("style");style.id="ib-custom-font-frame-style";(doc.head||doc.documentElement).appendChild(style)}
      style.textContent=active?frameStyle:"";
      if(active)doc.fonts?.load('16px "IBCustomFont"').catch(()=>{});
    }catch{}};
    if(!frame.dataset.ibFontHandler){frame.addEventListener("load",inject);frame.dataset.ibFontHandler="1";}
    inject();
  });
}
function initCustomFont(){
  const pick=document.getElementById("custom-font-file-input"),button=document.getElementById("import-custom-font"),toggle=document.getElementById("custom-font-enabled"),status=document.getElementById("custom-font-status");
  const placeCustomFontSetting=()=>{
    if(!toggle)return;
    const row=toggle.closest(".list-row") || toggle.closest(".setting-row");
    if(!row)return;
    const moduleRow=Array.from(document.querySelectorAll(".list-row, .setting-row"))
      .find(el=>el!==row && /module\s*optim(?:i|iz)ation/i.test((el.textContent||"").trim()));
    if(moduleRow && moduleRow.parentElement) moduleRow.parentElement.insertBefore(row,moduleRow);
  };
  placeCustomFontSetting();
  if(!pick||!button||!toggle)return;
  const storedFontPreference=localStorage.getItem("ibCustomFontEnabled");const enabled=storedFontPreference===null?uiSettings.customFontEnabled!==false:storedFontPreference==="1";toggle.checked=enabled;applyCustomFont(enabled);
  button.addEventListener("click",()=>pick.click());toggle.addEventListener("change",()=>{uiSettings.customFontEnabled=toggle.checked;persistUISettings();applyCustomFont(toggle.checked)});
  pick.addEventListener("change",async()=>{
    const file=pick.files?.[0];if(!file)return;
    try{
      if(!/\.ttf$/i.test(file.name))throw new Error("Choose a .ttf font file.");
      const bytes=new Uint8Array(await file.arrayBuffer()),magic=String.fromCharCode(...bytes.slice(0,4));
      const valid=bytes.length>=12&&((bytes[0]===0&&bytes[1]===1&&bytes[2]===0&&bytes[3]===0)||magic==="true"||magic==="OTTO");
      if(!valid)throw new Error("The file does not contain a recognized TrueType/OpenType font signature.");
      const encoded=btoa(Array.from(bytes,b=>String.fromCharCode(b)).join("")),temp=CUSTOM_FONT_PATH+".import-tmp";
      await runShell("mkdir -p "+shellQuote("/data/adb/modules/integrity-box/webroot")+" && rm -f "+shellQuote(temp));
      for(let i=0;i<encoded.length;i+=8000)await runShell("printf '%s' "+shellQuote(encoded.slice(i,i+8000))+" >> "+shellQuote(temp));
      await runShell("set -e; test -s "+shellQuote(temp)+"; base64 -d "+shellQuote(temp)+" > "+shellQuote(CUSTOM_FONT_PATH)+".new; test -s "+shellQuote(CUSTOM_FONT_PATH)+".new; mv -f "+shellQuote(CUSTOM_FONT_PATH)+".new "+shellQuote(CUSTOM_FONT_PATH)+"; rm -f "+shellQuote(temp)+"; chmod 0644 "+shellQuote(CUSTOM_FONT_PATH));
      if(status)status.textContent="Imported: "+file.name;
      toggle.checked=true;uiSettings.customFontEnabled=true;persistUISettings();applyCustomFont(true);
      document.fonts?.load('16px "IBCustomFont"').then(()=>popup("Custom font imported and applied","success")).catch(()=>popup("Font imported; browser could not load it, using default font","error"));
      popup("Custom font imported successfully","success");
    }catch(error){if(status)status.textContent="Import failed: "+(error.message||"Unknown error");popup(error.message||"Could not import custom font","error");}
    finally{pick.value=""}
  });
}
function initUIStyle(){
  const selector=document.getElementById("ui-layout-selector");
  if(!selector)return;
  const options=Array.from(selector.querySelectorAll("[data-layout]"));
  const apply=async layout=>{
    if(!["standard","modern","studio"].includes(layout))layout="standard";
    document.documentElement.classList.toggle("ui-alt",layout==="modern");
    document.documentElement.classList.toggle("ui-studio",layout==="studio");
    document.documentElement.classList.toggle("minimalist-active",layout==="studio");
    setMinimalAllActions(layout==="studio");
    options.forEach(option=>{
      const active=option.dataset.layout===layout;
      option.classList.toggle("active",active);
      option.setAttribute("aria-pressed",String(active));
      option.disabled=active;
    });
    const label=document.getElementById("ui-style-label");
    if(label)label.textContent=layout==="studio"?"Minimalist":layout.charAt(0).toUpperCase()+layout.slice(1);
    uiSettings.uiLayout=layout;
    uiSettings.uiStyle=layout==="modern";
    await persistUISettings();
  };
  apply(uiSettings.uiLayout|| (uiSettings.uiStyle?"modern":"studio"));
  options.forEach(option=>option.addEventListener("click",()=>{if(!option.disabled)apply(option.dataset.layout)}));
}


function initMinimalistCustomization(){
  const root=document.documentElement;
  const size=document.getElementById("tile-size-slider");
  const out=document.getElementById("tile-size-value");
  const reset=document.getElementById("tile-size-reset");
  const apply=value=>{
    let v=Number(value);
    if(!Number.isFinite(v))v=95;
    v=Math.min(200,Math.max(80,v));
    root.style.setProperty("--tile-scale",String(v/100));
    root.style.setProperty("--minimalist-tile-scale",String(v/100));
    if(size)size.value=String(v);
    if(out)out.textContent=v+"%";
    try{localStorage.setItem("ibTileSize",String(v));localStorage.setItem("ibMinimalistTileSize",String(v))}catch{}
  };
  let saved=95;
  try{saved=Number(localStorage.getItem("ibTileSize")||localStorage.getItem("ibMinimalistTileSize")||uiSettings.tileSize||95)}catch{}
  apply(saved);
  if(size&&!size.dataset.tileSizeBound){size.dataset.tileSizeBound="1";size.addEventListener("input",()=>apply(size.value));size.addEventListener("change",()=>apply(size.value))}
  reset?.addEventListener("click",()=>apply(UI_DEFAULTS.tileSize));
  root.classList.remove("minimalist-editing");
  document.querySelectorAll(".minimalist-move-controls").forEach(el=>el.remove());
  try{Object.keys(localStorage).filter(k=>k.startsWith("ibMinimalistOrder:")).forEach(k=>localStorage.removeItem(k))}catch{}
}

function initScale(){
  const slider=document.getElementById("ui-scale-slider"),value=document.getElementById("ui-scale-value"),app=document.querySelector(".app"),reset=document.getElementById("ui-scale-reset");
  if(!slider||!app)return;
  const apply=v=>{v=Math.min(120,Math.max(80,Number(v)||90));const scale=v/100;document.documentElement.style.setProperty("--ui-scale",String(scale));app.style.setProperty("--ui-scale",String(scale));app.style.setProperty("zoom",String(scale));slider.value=String(v);if(value)value.textContent=v+"%";uiSettings.scale=v;persistUISettings()};
  slider.addEventListener("input",()=>apply(slider.value));
  slider.addEventListener("change",()=>apply(slider.value));
  reset?.addEventListener("click",()=>apply(90));
  apply(uiSettings.scale);
}
function initExtractPage(){
  const page=document.getElementById("home-view-overview"),refresh=document.getElementById("extract-refresh"),info=document.getElementById("extract-info");
  if(!page)return;
  refresh?.addEventListener("click",()=>updateDashboard(true));
  document.getElementById("overview-copy")?.addEventListener("click",async()=>{
    const ids=["device","android","build","arch","cpu","kernel","user-apps","root","selinux","buildpatch","vendorpatch","fingerprint","runtime-uptime","store-current","store-code","store-history","gms-current","gms-code","gms-history","webview-package","webview-current","webview-state","LineageProp","selinux","pixel","patch","expiry","target","apps","zygote","zygiskless","blacklist","advanced","rom-spoofing","boot-hash","keybox"];
    const lines=ids.map(id=>{const el=document.getElementById("overview-"+id)||document.getElementById("status-"+id);return id+": "+(el?.textContent?.trim()||"Unavailable")});
    lines.push("Installed modules: "+(window.__systemOverviewModules||[]).map(m=>`${m.name} ${m.version} (${m.id})`).join(", "));
    try{await navigator.clipboard.writeText(lines.join("\n"));popup("System report copied","success")}catch{popup("Unable to copy report","error")}
  });
  const clearModal=document.getElementById("overview-clear-confirm");
  const closeClearModal=()=>{
    clearModal?.classList.remove("open");
    clearModal?.setAttribute("aria-hidden","true");
  };
  document.getElementById("overview-clear-gms")?.addEventListener("click",()=>{
    clearModal?.classList.add("open");
    clearModal?.setAttribute("aria-hidden","false");
  });
  document.getElementById("overview-clear-cancel")?.addEventListener("click",closeClearModal);
  clearModal?.addEventListener("click",event=>{if(event.target===clearModal)closeClearModal()});
  document.getElementById("overview-clear-confirm-action")?.addEventListener("click",async()=>{
    const button=document.getElementById("overview-clear-confirm-action");
    const trigger=document.getElementById("overview-clear-gms");
    if(button.disabled)return;
    button.disabled=true;
    button.textContent="Clearing…";
    if(trigger)trigger.disabled=true;
    try{
      const result=await runShell("pm clear com.android.vending && pm clear com.google.android.gms");
      if(!/Success/i.test(result))throw new Error(result||"The clear operation did not report success.");
      closeClearModal();
      popup("Google Play Store and Play Services data cleared","success");
    }catch(e){
      popup("Could not clear Google app data: "+e.message,"error");
    }finally{
      button.disabled=false;
      button.textContent="Clear data";
      if(trigger)trigger.disabled=false;
    }
  });
  document.getElementById("overview-stop-droidguard")?.addEventListener("click",async()=>{
    const button=document.getElementById("overview-stop-droidguard");button.disabled=true;
    try{
      await runShell("am force-stop com.google.android.gms.unstable && am force-stop com.google.android.gms && am force-stop com.android.vending");
      popup("Google services processes stopped","success");
    }catch(e){popup("Failed to stop Google services: "+e.message,"error")}
    finally{button.disabled=false}
  });
  info?.addEventListener("click",()=>{modalTitle.textContent="System Overview";modalOutput.textContent="System and device information is read from Android system properties. Google component versions are queried through package manager. Integrity Box indicators are read from their corresponding configuration files.";modalBackdrop.classList.remove("hidden")});
}
function initIntegrityCard(){
  const card=document.getElementById("home-integrity-card"),toggle=document.getElementById("integrity-toggle"),heading=document.querySelector(".integrity-status-heading");
  if(!card||!toggle)return;
  const apply=expanded=>{
    card.classList.toggle("collapsed",!expanded);
    toggle.setAttribute("aria-expanded",String(expanded));
    toggle.setAttribute("aria-label",expanded?"Minimize integrity status":"Expand integrity status");
    toggle.title=expanded?"Minimize integrity status":"Expand integrity status";
    heading?.classList.toggle("hidden",!expanded);
    setMinimalSettingsCardsHidden(!expanded);
  };
  apply(false);
  toggle.addEventListener("click",()=>apply(card.classList.contains("collapsed")));
}
function initTabs(){
  const navItems=Array.from(document.querySelectorAll(".nav-item"));
  if(!navItems.length)return;
  let currentIndex=Math.max(0,navItems.findIndex(n=>n.classList.contains("active")));
  if(currentIndex<0)currentIndex=0;
  const switchTab=index=>{
    if(index<0||index>=navItems.length)return;
    if(navItems[index].dataset.tab==="home")activateHomeSubtab("status");
    if(index===currentIndex)return;
    const current=document.getElementById("tab-"+(navItems[currentIndex].dataset.tab||""));
    const next=document.getElementById("tab-"+(navItems[index].dataset.tab||""));
    if(!current||!next)return;
    document.querySelectorAll(".tab-panel").forEach(panel=>{panel.classList.remove("active","enter-left","enter-right","exit-left","exit-right");panel.scrollTop=0});
    document.querySelectorAll(".nav-item").forEach(n=>n.classList.remove("active"));
    navItems[index].classList.add("active");
    next.classList.add("active");
    currentIndex=index;
  };
  navItems.forEach((item,index)=>item.addEventListener("click",e=>{e.preventDefault();e.stopPropagation();switchTab(index)}));
  const app=document.querySelector(".app");
  if(!app)return;
  let sx=0,sy=0,st=0;
  app.addEventListener("touchstart",e=>{
    if(document.documentElement.classList.contains("minimal-all-actions")||document.documentElement.classList.contains("ui-studio")){sx=sy=st=0;return}
    if(e.target.closest("button,a,input,select,textarea,.home-subtab,.log-scroll,.log-file"))return;
    const t=e.touches[0];sx=t.clientX;sy=t.clientY;st=Date.now();
  },{passive:true});
  app.addEventListener("touchend",e=>{
    if(document.documentElement.classList.contains("minimal-all-actions")||document.documentElement.classList.contains("ui-studio")){sx=sy=st=0;return}
    if(e.target.closest("button,a,input,select,textarea,.home-subtab,.log-scroll,.log-file"))return;
    const sw=document.getElementById("toggle-tab-swipe");
    if(sw&&!sw.checked)return;
    const t=e.changedTouches[0],dx=t.clientX-sx,dy=t.clientY-sy;
    if(Date.now()-st>350||Math.abs(dx)<60||Math.abs(dy)>Math.abs(dx)*1.35)return;
    switchTab(dx<0?currentIndex+1:currentIndex-1);
  },{passive:true});
}
function initModal(){modalClose?.addEventListener("click",()=>modalBackdrop.classList.add("hidden"));modalBackdrop?.addEventListener("click",e=>{if(e.target===modalBackdrop)modalBackdrop.classList.add("hidden")})}
function hideIntro(){
  const intro=document.getElementById("intro-overlay");
  if(!intro)return;
  let skip=false;
  skip=!!uiSettings.skipIntro
  if(skip){intro.remove();return}
  const dismiss=()=>{
    if(intro.dataset.dismissed)return;
    intro.dataset.dismissed="1";
    intro.classList.add("hidden");
    setTimeout(()=>intro.remove(),450);
  };
  intro.addEventListener("click",dismiss,{once:true});
  setTimeout(dismiss,850);
}

async function initUICache(){
  const toggle=document.getElementById("toggle-ui-cache");
  const key="ibUICache";
  const cacheName=UI_CACHE_NAME;
  let enabled=uiSettings.uiCache
  if(toggle)toggle.checked=enabled;
  const supported="caches" in window;
  const cacheAssets=async()=>{
    if(!supported)return;
    try{
      const cache=await caches.open(cacheName);
      const urls=[location.href,"style.css","script.js","icon.png","meowna.ttf","marked.min.js"];
      await Promise.all(urls.map(async url=>{try{const r=await fetch(url,{cache:"reload"});if(r.ok)await cache.put(url,r.clone())}catch{}}));
      if(window.i18nEnsureCached)await window.i18nEnsureCached(uiSettings.lang);
    }catch{}
  };
  const clearCache=async()=>{
    if(supported)try{
      const keys=await caches.keys();
      await Promise.all(keys.filter(key=>key.startsWith("integrity-box-ui-")).map(key=>caches.delete(key)));
    }catch{}
    try{window.i18nClearCache?.()}catch{}
  };
  if(enabled)cacheAssets();
  toggle?.addEventListener("change",async()=>{
    enabled=toggle.checked;
    uiSettings.uiCache=enabled;persistUISettings()
    if(enabled)await cacheAssets();
    else await clearCache();
  });
  if(enabled&&"serviceWorker" in navigator&&/^https?:$/.test(location.protocol)){
    try{await navigator.serviceWorker.register("service-worker.js",{scope:"./"})}catch{}
  }
  if(!enabled&&"serviceWorker" in navigator&&/^https?:$/.test(location.protocol)){
    try{const regs=await navigator.serviceWorker.getRegistrations();await Promise.all(regs.map(r=>r.unregister()))}catch{}
  }
}
const BOX_BACKUP_FORMAT="box-brain-backup";
function backupDecodeName(value){return decodeURIComponent(escape(atob(value)))}
async function backupDownload(data){
 const date=new Date().toISOString().slice(0,10),name=`box-brain-backup-${date}.json`,dir="/sdcard/Download",path=`${dir}/${name}`,temp=`${dir}/.${name}.transfer.tmp`,json=JSON.stringify(data,null,2),encoded=btoa(unescape(encodeURIComponent(json)));
 const writeChunk=async(chunk)=>runShell(`cat >> ${shellQuote(temp)} << 'IB_TRANSFER_CHUNK'\n${chunk}\nIB_TRANSFER_CHUNK`);
 await runShell(`mkdir -p ${shellQuote(dir)} && : > ${shellQuote(temp)}`);
 try{
  for(let i=0;i<encoded.length;i+=65536)await writeChunk(encoded.slice(i,i+65536));
  await runShell(`base64 -d ${shellQuote(temp)} > ${shellQuote(path)} && test -s ${shellQuote(path)} && rm -f ${shellQuote(temp)}`);
 }catch(e){try{await runShell(`rm -f ${shellQuote(temp)} ${shellQuote(path)}`)}catch{}throw new Error(`Could not save backup to ${path}. ${e.message}`)}
 return path;
}
async function backupReadFileBase64(path){
 const sizeRaw=await runShell(`wc -c < ${shellQuote(path)}`),size=parseInt(String(sizeRaw).trim(),10);
 if(!Number.isFinite(size)||size<0)throw new Error(`Unable to determine file size: ${path}`);
 if(size===0)return "";
 const encoded=String(await runShell(`base64 < ${shellQuote(path)} | tr -d '\\n'`)).replace(/[\r\n]/g,"");
 if(encoded.length!==Math.ceil(size/3)*4)throw new Error(`Incomplete Base64 read: ${path}`);
 return encoded;
}
async function createBoxBrainBackup(){
 const check=`set -e; [ -d ${shellQuote(BOXBRAIN)} ] || echo __IB_ERR_BOX__; [ -r ${shellQuote(UI_SETTINGS_FILE)} ] || echo __IB_ERR_SETTINGS__; [ -d ${shellQuote(`${BOXBRAIN}/PIF`)} ] || echo __IB_ERR_PIF__; find ${shellQuote(BOXBRAIN)} -maxdepth 1 -type f -print; find ${shellQuote(`${BOXBRAIN}/PIF`)} -maxdepth 1 -type f -print`;
 const listing=await runShell(check);
 if(listing.includes("__IB_ERR_"))throw new Error(listing.includes("__IB_ERR_SETTINGS__")?"UI settings file is missing or unreadable.":listing.includes("__IB_ERR_PIF__")?"PIF directory is missing or unreadable.":"Box-Brain directory is missing or inaccessible.");
 const paths=listing.split(/\r?\n/).map(x=>x.trim()).filter(x=>x.startsWith(BOXBRAIN));
 const backup={format:BOX_BACKUP_FORMAT,version:1,createdAt:new Date().toISOString(),settings:null,files:{},pif:{}};
 for(const path of [UI_SETTINGS_FILE,...paths]){
  if(path===UI_SETTINGS_FILE){backup.settings={type:"base64",encoding:"base64",content:await backupReadFileBase64(path)};continue;}
  const name=path.slice(path.lastIndexOf("/")+1);
  if(!/^[A-Za-z0-9._-]+$/.test(name)||name==="."||name===".."||(name==="integrity_box_ui_settings"&&path===BOXBRAIN))continue;
  const content=await backupReadFileBase64(path),entry=content?{type:"base64",encoding:"base64",content}:{type:"empty"};
  if(path.startsWith(`${BOXBRAIN}/PIF/`))backup.pif[name]=entry;else backup.files[name]=entry;
 }
 if(!backup.settings)throw new Error("Could not read UI settings.");
 JSON.parse(decodeURIComponent(escape(atob(backup.settings.content))));
 const savedPath=await backupDownload(backup);popup(`Backup saved to ${savedPath}`,"success");
}
function validateBoxBackup(data){
 if(!data||typeof data!=="object"||Array.isArray(data)||data.format!==BOX_BACKUP_FORMAT||data.version!==1)throw new Error("Unsupported backup format or version.");
 const validEntry=e=>{if(!e||typeof e!=="object"||Array.isArray(e))return false;if(e.type==="empty")return e.content===undefined;if(e.type==="base64")return e.encoding==="base64"&&typeof e.content==="string"&&/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(e.content);if(e.type==="text")return typeof e.content==="string";return false};
 if(!validEntry(data.settings)||data.settings.type==="empty")throw new Error("The backup has missing or invalid UI settings.");try{JSON.parse(data.settings.type==="text"?data.settings.content:decodeURIComponent(escape(atob(data.settings.content))))}catch{throw new Error("The backup contains invalid UI settings JSON.")}
 for(const key of ["files","pif"]){if(!data[key]||typeof data[key]!=="object"||Array.isArray(data[key]))throw new Error(`The backup has an invalid ${key} section.`);for(const [name,e] of Object.entries(data[key])){if(!/^[A-Za-z0-9._-]+$/.test(name)||name==="."||name===".."||(name==="integrity_box_ui_settings"&&key==="files"))throw new Error(`Invalid filename in backup: ${name}`);if(!validEntry(e))throw new Error(`Invalid file entry: ${name}`)}}return true;
}
function entryBytes(entry){if(entry.type==="empty")return "";if(entry.type==="base64")return entry.content;return btoa(unescape(encodeURIComponent(entry.content)))}
const BACKUP_SETTING_LABELS={fullscreen:"Fullscreen mode",backgroundMusic:"Background music",edgeSwipe:"Edge swipe navigation",edgeTap:"Edge tap to back",backButton:"Floating back button",tabSwipe:"Tab swipe navigation",gestureRight:"Right-edge gesture",openingToasts:"Opening notifications",skipIntro:"Skip intro",uiLayout:"UI layout",uiCache:"UI asset caching"};
const BACKUP_FLAG_LABELS={
 "spoof-los-boot":"Hide Lineage",
 "nuke-los-boot":"Nuke Lineage",
 "spoof-custom-rom-boot":"Hide Custom ROM",
 "NoLineageProp":"Spoof Lineage Props",
 nodebug:"Debug Fingerprint",
 build:"Debug Build",
 tag:"Build Tag",
 encrypt:"Spoof Encryption",
 "spoof-selinux-boot":"Spoof SELinux",
 "nuke-sus-boot":"Hide SUS Files",
 twrp:"Hide Recovery",
 skip:"Skip Patch Spoofing",
 zygisk:"Zygiskless Mode",
 "force-reset":"Aggressive Mode",
 hidehook:"Hide Hook Detection",
 disablegms:"Pause built-in GMS spoofing",
 disablevending:"Pause built-in Play Store spoofing",
 safemode:"Safe Mode"
};
let pendingBackupRestore=null;
function backupEscapeHtml(value){return String(value).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]))}
function decodeBackupEntryText(entry){
 if(!entry||entry.type==="empty")return "";
 if(entry.type==="text")return entry.content;
 if(entry.type==="base64")return decodeURIComponent(escape(atob(entry.content)));
 return "";
}
function backupPreviewItems(container,items,emptyText){
 container.innerHTML="";
 if(!items.length){container.innerHTML=`<div class="backup-preview-empty">${backupEscapeHtml(emptyText)}</div>`;return}
 for(const item of items){
  const row=document.createElement("div");row.className="backup-preview-item";
  row.innerHTML=`<span class="mark">✓</span><span>${backupEscapeHtml(item)}</span>`;
  container.appendChild(row);
 }
}
function prepareBackupPreview(file,data){
 const settings=JSON.parse(decodeBackupEntryText(data.settings));
 const enabledSettings=Object.entries(BACKUP_SETTING_LABELS).filter(([key])=>settings[key]===true).map(([,label])=>label);
 enabledSettings.unshift(`UI scale: ${Number.isFinite(Number(settings.scale))?settings.scale+"%":"default"}`);
 if(typeof settings.lang==="string"&&settings.lang)enabledSettings.push(`Language: ${settings.lang}`);
 const enabledFlags=[];
 for(const [id,label] of Object.entries(BACKUP_FLAG_LABELS)){
  if(Object.prototype.hasOwnProperty.call(data.files,id))enabledFlags.push(label);
 }
 if(data.pif&&Object.prototype.hasOwnProperty.call(data.pif,"advanced"))enabledFlags.push("Advanced Spoofing");
 const blacklistEntry=data.files["blacklist.txt"];
 const apps=blacklistEntry?decodeBackupEntryText(blacklistEntry).split(/\r?\n/).map(v=>v.trim()).filter(Boolean):[];
 document.getElementById("backup-confirm-filename").textContent=file.name;
 backupPreviewItems(document.getElementById("backup-preview-settings"),enabledSettings,"No interface options are enabled in this backup.");
 backupPreviewItems(document.getElementById("backup-preview-flags"),enabledFlags,"No recognized boot/module feature flags are enabled in this backup.");
 backupPreviewItems(document.getElementById("backup-preview-blacklist"),apps.map(app=>app),"No apps are listed in blacklist.txt.");
 const overlay=document.getElementById("backup-confirm-overlay");
 overlay.hidden=false;
 document.body.style.overflow="hidden";
}
function closeBackupPreview(){
 const overlay=document.getElementById("backup-confirm-overlay");
 if(overlay)overlay.hidden=true;
 document.body.style.overflow="";
 pendingBackupRestore=null;
}
async function restoreBoxBrainBackup(data){
 const staged=[];const add=(path,entry)=>staged.push({path,encoded:entryBytes(entry)});
 add(UI_SETTINGS_FILE,data.settings);for(const [name,e] of Object.entries(data.files))add(`${BOXBRAIN}/${name}`,e);for(const [name,e] of Object.entries(data.pif))add(`${BOXBRAIN}/PIF/${name}`,e);
 const stageRoot=`${BOXBRAIN}/.backup-restore-${Date.now()}`,chunkSize=65536;
 try{
  await runShell(`set -e; mkdir -p ${shellQuote(`${BOXBRAIN}/PIF`)} ${shellQuote(stageRoot)}`);
  for(let i=0;i<staged.length;i++){
   const item=staged[i],temp=`${stageRoot}/${i}.b64`,decoded=`${stageRoot}/${i}`;
   await runShell(`: > ${shellQuote(temp)}`);
   for(let j=0;j<item.encoded.length;j+=chunkSize){
    const chunk=item.encoded.slice(j,j+chunkSize);
    await runShell(`cat >> ${shellQuote(temp)} << 'IB_RESTORE_CHUNK'\n${chunk}\nIB_RESTORE_CHUNK`);
   }
   await runShell(`base64 -d ${shellQuote(temp)} > ${shellQuote(decoded)}`);item.decoded=decoded;
  }
  for(const item of staged){
   const dir=item.path.slice(0,item.path.lastIndexOf("/")),tmp=item.path+".ib-restore-tmp";
   await runShell(`mkdir -p ${shellQuote(dir)}; cat ${shellQuote(item.decoded)} > ${shellQuote(tmp)}; mv -f ${shellQuote(tmp)} ${shellQuote(item.path)}`);
  }
  await runShell(`rm -rf ${shellQuote(stageRoot)}`);
 }catch(e){try{await runShell(`rm -rf ${shellQuote(stageRoot)}; find ${shellQuote(BOXBRAIN)} -maxdepth 2 -type f -name '*.ib-restore-tmp' -delete`)}catch{}throw new Error("Restore failed; temporary files were cleaned where possible. "+e.message)}
 try{for(const key of Object.keys(localStorage))if(key.startsWith("ib"))localStorage.removeItem(key);await loadUISettings();if(window.i18nSetLanguage)await window.i18nSetLanguage(uiSettings.lang)}catch{}popup("Backup restored successfully","success");setTimeout(()=>location.reload(),400);
}
function initBackupRestore(){
 const create=document.getElementById("create-backup"),choose=document.getElementById("choose-backup"),input=document.getElementById("backup-file-input"),selected=document.getElementById("backup-selected");
 const overlay=document.getElementById("backup-confirm-overlay"),cancel=document.getElementById("backup-restore-cancel"),close=document.getElementById("backup-confirm-close"),confirmButton=document.getElementById("backup-restore-confirm");
 if(!create||!choose||!input)return;
 create.addEventListener("click",async()=>{create.disabled=true;try{await createBoxBrainBackup()}catch(e){popup(e.message||"Backup failed","error")}finally{create.disabled=false}});
 choose.addEventListener("click",()=>input.click());
 input.addEventListener("change",async()=>{
  const file=input.files&&input.files[0];
  if(!file){input.value="";return}
  selected.textContent=`Selected: ${file.name}`;
  try{
   if(!file.name.toLowerCase().endsWith(".json"))throw new Error("Select a .json backup file.");
   if(file.size>20*1024*1024)throw new Error("Backup file is larger than the 20 MB limit.");
   let data;try{data=JSON.parse(await file.text())}catch{throw new Error("The selected file is not valid JSON.")}
   validateBoxBackup(data);
   pendingBackupRestore={file,data};
   prepareBackupPreview(file,data);
  }catch(e){popup(e.message||"Invalid backup file","error")}
  finally{input.value=""}
 });
 const cancelPreview=()=>closeBackupPreview();
 cancel?.addEventListener("click",cancelPreview);
 close?.addEventListener("click",cancelPreview);
 overlay?.addEventListener("click",event=>{if(event.target===overlay)cancelPreview()});
 document.addEventListener("keydown",event=>{if(event.key==="Escape"&&overlay&&!overlay.hidden)cancelPreview()});
 confirmButton?.addEventListener("click",async()=>{
  if(!pendingBackupRestore)return;
  const pending=pendingBackupRestore;
  confirmButton.disabled=true;cancel.disabled=true;close.disabled=true;
  confirmButton.textContent="Restoring…";
  try{await restoreBoxBrainBackup(pending.data);closeBackupPreview()}
  catch(e){popup(e.message||"Restore failed","error")}
  finally{confirmButton.disabled=false;cancel.disabled=false;close.disabled=false;confirmButton.textContent="Restore backup"}
 });
}

initLogFileToggle();
initBackupRestore();
initLogCopy();
initLogRefresh();
function closeUIResetConfirm(){
  document.getElementById("reset-ui-confirm")?.classList.add("hidden");
}
function openUIResetConfirm(){
  const modal=document.getElementById("reset-ui-confirm");
  if(!modal)return;
  modal.classList.remove("hidden");
}
async function resetAllUISettings(){
  uiSettings={...UI_DEFAULTS};
  try{
    ["ibUiScale","ibTileSize","ibCustomFontEnabled","ibFullscreen","ibAnimatedBackground","ibMonochromeTheme","ibBackgroundMusic","ibEdgeSwipe","ibEdgeTap","ibBackButton","ibTabSwipe","ibGestureRight","ibOpeningToasts","ibSkipIntro","ibUIStyle","ibUILayout","ibUICache","ibLang"].forEach(key=>localStorage.removeItem(key));
    Object.keys(localStorage).filter(key=>key.indexOf("ibI18nCache:")===0).forEach(key=>localStorage.removeItem(key));
  }catch{}
  try{window.i18nClearCache?.()}catch{}
  await persistUISettings();
  location.reload();
}
function initUIReset(){
  const open=document.getElementById("reset-ui-button");
  const cancel=document.getElementById("reset-ui-cancel");
  const confirm=document.getElementById("reset-ui-confirm-button");
  const modal=document.getElementById("reset-ui-confirm");
  if(!open||!cancel||!confirm||!modal)return;
  open.addEventListener("click",openUIResetConfirm);
  cancel.addEventListener("click",closeUIResetConfirm);
  confirm.addEventListener("click",resetAllUISettings);
  modal.addEventListener("click",e=>{if(e.target===modal)closeUIResetConfirm()});
  document.addEventListener("keydown",e=>{if(e.key==="Escape"&&!modal.classList.contains("hidden"))closeUIResetConfirm()});
}
document.addEventListener("DOMContentLoaded",async()=>{
  try{await (window.__ibI18nReady||Promise.resolve())}catch{}
  try{await loadUISettings()}catch{}
  try{await runKsuNextCompatibility()}catch{}
  try{await updateKsuNextStatus()}catch{}
  try{if(window.i18nSetLanguage&&uiSettings.lang!==window.__ibI18nState?.lang)await window.i18nSetLanguage(uiSettings.lang)}catch{}
  hideIntro();
  try{initIntegrityCard()}catch(e){console.error("initIntegrityCard",e)}
  try{refreshKeyboxStatus(true)}catch(e){console.error("keybox status",e)}
  try{updateModuleVersion().then(version=>{if(!version)setTimeout(updateModuleVersion,900)}).catch(e=>console.error("module version",e))}catch(e){console.error("module version",e)}
  try{initTabs()}catch(e){console.error("initTabs",e)}
  try{initHomeSubtabs()}catch(e){console.error("initHomeSubtabs",e)}
  try{initExtractPage()}catch(e){console.error("initExtractPage",e)}
  try{initInterfaceSettings()}catch(e){console.error("initInterfaceSettings",e)}
  try{initLanguageSelector()}catch(e){console.error("initLanguageSelector",e)}
  try{initScale()}catch(e){console.error("initScale",e)}
  try{initUIStyle()}catch(e){console.error("initUIStyle",e)}
  try{initCustomFont()}catch(e){console.error("initCustomFont",e)}
  try{initMinimalistCustomization()}catch(e){console.error("initMinimalistCustomization",e)}
  try{initUICache()}catch(e){console.error("initUICache",e)}   try{initUIReset()}catch(e){console.error("initUIReset",e)}
  try{document.getElementById("refresh-announcements")?.addEventListener("click",()=>loadAnnouncements(true))}catch(e){console.error("announcements",e)}
  try{attachButtonListeners()}catch(e){console.error("buttons",e)}
  try{initModal()}catch(e){console.error("modal",e)}
  try{loadAnnouncements()}catch(e){console.error("loadAnnouncements",e)}
  try{initAnnouncementImageViewer()}catch(e){console.error("announcement image viewer",e)}
});
