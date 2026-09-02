const TARGET_FILE="/data/adb/modules/playintegrityfix/apps.txt";
const PROP_FILE="/data/adb/modules/playintegrityfix/custom.pif.prop";
const FLAG_FILE="/data/adb/Box-Brain/per-app-spoofing";
const ZYGISK_PATH="/data/adb/modules/playintegrityfix/zygisk";
const BACKUP_DIR="/sdcard/Download/DeviceSpoofer";

function runShell(cmd,cb){
  if(window.parent?.runShellFromIframe){
    window.parent.runShellFromIframe(cmd).then(out=>cb?.(0,out,"")).catch(err=>cb?.(1,"",err));
  }else if(window.ksu?.exec){
    const id="cb_"+Date.now()+"_"+Math.floor(Math.random()*9999);
    window[id]=(code,stdout,stderr)=>{try{delete window[id]}catch(e){};cb?.(code,stdout||"",stderr||"");};
    ksu.exec(cmd,"{}",id);
  }else cb?.(1,"","ksu/runShell not found");
}

function esc(s){return"'"+String(s).replace(/'/g,"'\\''")+"'";}

function popup(msg,type){
  if(!type)type="info";
  try{
    if(typeof window.toast==="function"){window.toast(String(msg));return;}
    if(window.kernelsu&&typeof window.kernelsu.toast==="function"){window.kernelsu.toast(String(msg));return;}
    if(typeof ksu==="object"&&typeof ksu.toast==="function"){ksu.toast(String(msg));return;}
  }catch(e){}
  let toast=document.getElementById("toast");
  if(!toast){
    toast=document.createElement("div");
    toast.id="toast";
    toast.className="toast";
    document.body.appendChild(toast);
  }
  toast.textContent=msg;
  requestAnimationFrame(()=>toast.classList.add("show"));
  clearTimeout(toast._timer);
  toast._timer=setTimeout(()=>toast.classList.remove("show"),2500);
}

function readLines(path,cb){
  runShell("if [ -f "+esc(path)+" ]; then cat "+esc(path)+"; fi",(c,o)=>{
    cb((o||"").split("\n").map(l=>l.trim()).filter(l=>l));
  });
}

function writeLines(path,lines,cb){
  if(lines.length===0){runShell("> "+esc(path),c=>cb?.(c===0));return;}
  const args=lines.map(l=>esc(l)).join(" ");
  runShell("mkdir -p $(dirname "+esc(path)+") && printf '%s\\n' "+args+" > "+esc(path),c=>cb?.(c===0));
}

async function readKey(file,key){
  return new Promise(resolve=>{
    const cmd="sh -c 'grep -m1 \"^"+key+"=\" \""+file+"\" | cut -d\"=\" -f2- || echo \"\"'";
    runShell(cmd,(c,o)=>resolve((o||"").toString().trim()));
  });
}

async function writeKey(file,key,value){
  return new Promise(resolve=>{
    const cmd="sh -c 'if grep -q \"^"+key+"=.*\" \""+file+"\" 2>/dev/null; then sed -i \"s/^"+key+"=.*/"+key+"="+value+"/\" \""+file+"\"; else printf \"\\n"+key+"="+value+"\\n\" >> \""+file+"\"; fi'";
    runShell(cmd,c=>resolve(c===0));
  });
}

async function checkZygisk(){
  return new Promise(resolve=>{
    runShell("sh -c 'if [ -d \""+ZYGISK_PATH+"\" ]; then echo exists; else echo missing; fi'",(c,o)=>resolve((o||"").trim()==="exists"));
  });
}

let cachedApps=[];
let zygiskExists=false;
let spoofAppsEnabled=false;
let showSystem=false;

function fetchApps(system,cb){
  const flag=system?"-s":"-3";
  const cmd="pm list packages "+flag+" -f | while IFS= read -r line; do pkg=\"${line##*=}\"; apk=\"${line#package:}\"; apk=\"${apk%%=*}\"; label=\"$pkg\"; if command -v aapt >/dev/null 2>&1; then l=$(aapt d badging \"$apk\" 2>/dev/null | grep \"application-label:\" | head -1 | cut -d\"'\" -f2); [ -n \"$l\" ] && label=\"$l\"; fi; echo \"$pkg|$label\"; done";
  runShell(cmd,(c,out)=>{
    if(!out)return cb([]);
    const apps=out.trim().split("\n").map(l=>{
      const i=l.indexOf("|");
      return{pkg:i>0?l.slice(0,i):l,label:i>0?l.slice(i+1):l,system:system};
    }).filter(a=>a.pkg);
    cb(apps);
  });
}

function buildList(){
  readLines(TARGET_FILE,tLines=>{
    if(showSystem){
      fetchApps(true,sysApps=>{
        fetchApps(false,userApps=>{
          cachedApps=[...userApps,...sysApps];
          sortAndRender(cachedApps,tLines);
          updateStatusBar(tLines.length);
        });
      });
    }else{
      fetchApps(false,apps=>{
        cachedApps=apps;
        sortAndRender(cachedApps,tLines);
        updateStatusBar(tLines.length);
      });
    }
  });
}

function sortAndRender(apps,targets){
  const q=(document.getElementById("search").value||"").toLowerCase();
  const list=document.getElementById("list");
  const empty=document.getElementById("emptyState");
  const loading=document.getElementById("loadingRow");
  loading.style.display="none";
  list.style.display="flex";
  list.innerHTML="";
  let visibleCount=0;

  const filtered=apps.filter(a=>!q||a.pkg.toLowerCase().includes(q)||a.label.toLowerCase().includes(q));
  filtered.sort((a,b)=>{
    const ta=targets.includes(a.pkg);
    const tb=targets.includes(b.pkg);
    if(ta&&!tb)return-1;
    if(!ta&&tb)return 1;
    return a.label.localeCompare(b.label);
  });

  filtered.forEach(a=>{
    visibleCount++;
    const isTarget=targets.includes(a.pkg);
    const item=document.createElement("div");
    item.className="item"+(isTarget?" on":"");
    item.setAttribute("data-pkg",a.pkg);
    item.innerHTML='<img class="app-icon" data-src="ksu://icon/'+a.pkg+'" alt=""><div class="info"><div class="name">'+(a.label||a.pkg)+'</div></div><div class="item-toggle '+(isTarget?"active":"")+'"></div>';
    list.appendChild(item);
  });

  empty.classList.toggle("show",visibleCount===0);
  attachListeners();
  loadIcons();
}

function attachListeners(){
  document.querySelectorAll(".item").forEach(item=>{
    item.onclick=()=>{
      if(!zygiskExists)return;
      const pkg=item.getAttribute("data-pkg");
      const isOn=item.classList.contains("on");
      readLines(TARGET_FILE,lines=>{
        let newTargets=[...lines];
        if(isOn)newTargets=newTargets.filter(p=>p!==pkg);
        else if(!newTargets.includes(pkg))newTargets.push(pkg);
        writeLines(TARGET_FILE,newTargets,ok=>{
          popup(ok?(isOn?"Removed from targets":"Added to targets"):"Write failed",!ok?"error":"");
          buildList();
        });
      });
    };
  });
}

document.getElementById("search").addEventListener("input",buildList);

function loadIcons(){
  const imgs=document.querySelectorAll("img.app-icon[data-src]");
  if(!("IntersectionObserver"in window)){
    imgs.forEach(img=>{img.src=img.dataset.src;});
    return;
  }
  const obs=new IntersectionObserver(entries=>{
    entries.forEach(e=>{
      if(!e.isIntersecting)return;
      const img=e.target;
      img.src=img.dataset.src;
      img.onload=()=>{};
      img.onerror=()=>img.style.display="none";
      obs.unobserve(img);
    });
  },{rootMargin:"50px"});
  imgs.forEach(img=>obs.observe(img));
}

function toggleSystemApps(){
  showSystem=!showSystem;
  document.getElementById("sysBtn").classList.toggle("btn-primary",showSystem);
  buildList();
}

function getVisiblePackages(){
  const q=(document.getElementById("search").value||"").toLowerCase();
  return cachedApps.filter(a=>!q||a.pkg.toLowerCase().includes(q)||a.label.toLowerCase().includes(q)).map(a=>a.pkg);
}

function selectAllVisible(){
  if(!zygiskExists)return;
  const visible=getVisiblePackages();
  if(!visible.length)return;
  readLines(TARGET_FILE,lines=>{
    const newTargets=[...new Set([...lines,...visible])];
    writeLines(TARGET_FILE,newTargets,ok=>{
      popup(ok?"Added all visible apps":"Write failed",!ok?"error":"");
      buildList();
    });
  });
}

function deselectAllVisible(){
  if(!zygiskExists)return;
  const visible=getVisiblePackages();
  if(!visible.length)return;
  readLines(TARGET_FILE,lines=>{
    const newTargets=lines.filter(p=>!visible.includes(p));
    writeLines(TARGET_FILE,newTargets,ok=>{
      popup(ok?"Removed all visible apps":"Write failed",!ok?"error":"");
      buildList();
    });
  });
}

async function toggleSpoofApps(){
  if(!zygiskExists)return;
  const newVal=spoofAppsEnabled?"0":"1";
  await writeKey(PROP_FILE,"spoofApps",newVal);
  if(newVal==="1")runShell("mkdir -p $(dirname "+esc(FLAG_FILE)+") && touch "+esc(FLAG_FILE),()=>{});
  else runShell("rm -f "+esc(FLAG_FILE),()=>{});
  spoofAppsEnabled=!spoofAppsEnabled;
  updateSpoofAppsVisuals();
  updateStatusBar();
  popup(spoofAppsEnabled?"Spoof Apps enabled":"Spoof Apps disabled");
}

function updateSpoofAppsVisuals(){
  const row=document.getElementById("spoofAppsRow");
  const input=document.getElementById("spoofAppsInput");
  row.classList.toggle("on",spoofAppsEnabled);
  row.style.borderColor=spoofAppsEnabled?"var(--accent)":"";
  input.checked=spoofAppsEnabled;
}

function updateStatusBar(count){
  const zygiskChip=document.getElementById("zygiskChip");
  const spoofChip=document.getElementById("spoofChip");
  const countChip=document.getElementById("countChip");
  const badge=document.getElementById("appsBadge");

  zygiskChip.classList.toggle("active",zygiskExists);
  zygiskChip.querySelector(".text").textContent=zygiskExists?"Zygisk Active":"Zygisk Missing";

  spoofChip.classList.toggle("active",spoofAppsEnabled);
  spoofChip.querySelector(".text").textContent=spoofAppsEnabled?"Spoofing On":"Spoofing Off";

  if(typeof count==="number"){
    countChip.textContent=count+" app"+(count!==1?"s":"");
    badge.textContent=count;
  }else{
    readLines(TARGET_FILE,lines=>{
      const c=lines.length;
      countChip.textContent=c+" app"+(c!==1?"s":"");
      badge.textContent=c;
    });
  }
}

function lockUI(){
  document.getElementById("lockedOverlay").classList.add("show");
  document.getElementById("warningBanner").classList.add("show");
  document.getElementById("search").disabled=true;
  document.getElementById("spoofAppsRow").style.pointerEvents="none";
  document.getElementById("spoofAppsRow").style.opacity="0.4";
}

function showInfo(e){
  e.stopPropagation();
  const tip=document.getElementById("infoTooltip");
  tip.classList.toggle("show");
  if(tip.classList.contains("show")){
    setTimeout(()=>tip.classList.remove("show"),8000);
  }
}

/* Backup / Restore */
function openBackupModal(){
  const now=new Date();
  const name="apps_"+now.getFullYear()+(now.getMonth()+1).toString().padStart(2,"0")+now.getDate().toString().padStart(2,"0")+"_"+now.getHours().toString().padStart(2,"0")+now.getMinutes().toString().padStart(2,"0")+".txt";
  const path=BACKUP_DIR+"/"+name;
  runShell("mkdir -p "+esc(BACKUP_DIR)+" && cp "+esc(TARGET_FILE)+" "+esc(path)+" 2>/dev/null; echo $?",(c,o)=>{
    if((o||"").trim()==="0"&&c===0){
      popup("Backup saved to "+name,"success");
    }else{
      popup("Backup failed","error");
    }
  });
}

function openRestoreModal(){
  runShell("ls -1 "+esc(BACKUP_DIR)+"/*.txt 2>/dev/null || echo ''",(c,out)=>{
    const files=(out||"").trim().split("\n").filter(f=>f);
    const overlay=document.getElementById("modalOverlay");
    const title=document.getElementById("modalTitle");
    const body=document.getElementById("modalBody");
    const actions=document.getElementById("modalActions");

    title.textContent="Restore Backup";
    body.innerHTML="";
    actions.innerHTML='<button class="btn btn-block" onclick="closeModal()">Close</button>';

    if(!files.length||files[0]===""){
      body.innerHTML='<div class="muted small" style="text-align:center;padding:20px">No backups found</div>';
    }else{
      files.forEach(f=>{
        const fname=f.replace(/^.*\//,"");
        const div=document.createElement("div");
        div.className="backup-item";
        div.onclick=()=>restoreBackup(f);
        div.innerHTML='<div><div class="bname">'+fname+'</div><div class="bsize">'+f+'</div></div><span class="muted">&rsaquo;</span>';
        body.appendChild(div);
      });
    }
    overlay.classList.add("show");
  });
}

function restoreBackup(path){
  runShell("cp "+esc(path)+" "+esc(TARGET_FILE)+" 2>/dev/null; echo $?",(c,o)=>{
    if((o||"").trim()==="0"&&c===0){
      popup("Backup restored","success");
      closeModal();
      buildList();
    }else{
      popup("Restore failed","error");
    }
  });
}

function closeModal(){
  document.getElementById("modalOverlay").classList.remove("show");
}

async function init(){
  zygiskExists=await checkZygisk();
  if(!zygiskExists){
    lockUI();
    updateStatusBar(0);
    buildList();
    return;
  }
  const val=await readKey(PROP_FILE,"spoofApps");
  const flagExists=await new Promise(resolve=>{
    runShell("if [ -f "+esc(FLAG_FILE)+" ]; then echo exists; else echo missing; fi",(c,o)=>resolve((o||"").trim()==="exists"));
  });
  spoofAppsEnabled=val==="1"||flagExists;
  if(spoofAppsEnabled&&val!=="1")await writeKey(PROP_FILE,"spoofApps","1");
  if(!spoofAppsEnabled&&flagExists)runShell("rm -f "+esc(FLAG_FILE),()=>{});
  updateSpoofAppsVisuals();
  updateStatusBar();
  runShell("mkdir -p $(dirname "+esc(TARGET_FILE)+") && touch "+esc(TARGET_FILE),()=>buildList());
}

init();
