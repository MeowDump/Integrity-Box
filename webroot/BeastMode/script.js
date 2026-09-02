const DIR="/data/adb/Box-Brain";
const LOG_FILE=DIR+"/Integrity-Box-Logs/beastmode.log";
const PREFS_FILE=DIR+"/beastmode_prefs";
const BANKING_FLAG=DIR+"/banking_mode";

const scripts=[
  {name:"Update Spoofing",path:"/data/adb/modules/playintegrityfix/osm0sis.sh"},
  {name:"Update Keybox",path:"/data/adb/modules/playintegrityfix/webroot/common_scripts/key.sh"},
  {name:"Update HMA",path:"/data/adb/modules/playintegrityfix/webroot/common_scripts/hma.sh"},
  {name:"Spoof Lineage",path:"/data/adb/modules/playintegrityfix/webroot/common_scripts/override_lineage.sh"},
  {name:"Delete Lineage",path:"/data/adb/modules/playintegrityfix/webroot/common_scripts/force_override.sh"},
  {name:"Hide ROM Props",path:"/data/adb/modules/playintegrityfix/webroot/common_scripts/prop.sh"},
  {name:"Update Targets",path:"/data/adb/modules/playintegrityfix/webroot/common_scripts/target.sh"},
  {name:"Hide SUS Files",path:"/data/adb/modules/playintegrityfix/webroot/common_scripts/susfiles.sh"}
];

const selected=new Set();
let execQueue=[];
let execIdx=0;
let bankingBusy=false;

function popup(msg,type="info"){
  try{
    if(typeof window.toast==="function"){window.toast(String(msg));return}
    if(window.kernelsu&&typeof window.kernelsu.toast==="function"){window.kernelsu.toast(String(msg));return}
    if(typeof ksu==="object"&&typeof ksu.toast==="function"){ksu.toast(String(msg));return}
  }catch{}
  const n=document.createElement("div");
  n.className="toast";
  n.textContent=msg;
  document.body.appendChild(n);
  requestAnimationFrame(()=>n.classList.add("show"));
  setTimeout(()=>{n.classList.remove("show");setTimeout(()=>n.remove(),300)},2800);
}

function showLoader(show,text){
  const loader=document.getElementById("loader");
  const loaderText=document.getElementById("loaderText");
  if(text)loaderText.textContent=text;
  if(show){
    loader.classList.add("show");
  }else{
    loader.classList.remove("show");
  }
}

let RESET_PROP_INFO = null;

function detectResetprop(){
  if(RESET_PROP_INFO !== null) return RESET_PROP_INFO;

  // Try "which resetprop" first
  let rpPath = "";
  try{
    rpPath = String(ksu.exec("which resetprop 2>/dev/null || echo ''")).trim();
  }catch(e){}

  // Fallback to known paths
  if(!rpPath){
    const paths = [
      "/data/adb/ksu/bin/resetprop",
      "/data/adb/ap/bin/resetprop",
      "/data/adb/magisk/resetprop",
      "/data/adb/magisk/busybox resetprop",
      "/sbin/resetprop",
      "/system/xbin/resetprop",
      "/system/bin/resetprop"
    ];
    for(const p of paths){
      try{
        const r = ksu.exec("test -f '" + p.split(" ")[0] + "' && echo FOUND || echo NOT_FOUND");
        if(String(r).trim() === "FOUND"){
          rpPath = p;
          break;
        }
      }catch(e){}
    }
  }

  if(!rpPath){
    RESET_PROP_INFO = {path: "resetprop", dir: "", isCompact: false};
    return RESET_PROP_INFO;
  }

  // Detect if compact resetprop
  let isCompact = false;
  try{
    const help = String(ksu.exec(rpPath + " --help 2>&1 || echo ''")).trim();
    if(help && !help.includes("-p") && !help.includes("--persist")){
      isCompact = true;
    }
  }catch(e){}

  const dir = rpPath.includes("/") ? rpPath.substring(0, rpPath.lastIndexOf("/")) : "";
  RESET_PROP_INFO = {path: rpPath, dir: dir, isCompact: isCompact};
  return RESET_PROP_INFO;
}

function getResetpropCmd(){
  const info = detectResetprop();
  return info.path;
}

function getResetpropSetCmd(key, value, persistent){
  const info = detectResetprop();
  const rp = info.path;

  if(info.isCompact){
    if(persistent){
      return rp + " -n " + key + " " + value;
    }
    return rp + " " + key + " " + value;
  }

  if(persistent){
    return rp + " -p " + key + " " + value;
  }
  return rp + " " + key + " " + value;
}

function getResetpropDeleteCmd(key, persistent){
  const info = detectResetprop();
  const rp = info.path;

  if(info.isCompact){
    return rp + " -d " + key;
  }

  if(persistent){
    return rp + " -p -d " + key;
  }
  return rp + " -d " + key;
}

function sh(cmd){
  try{
    const info = detectResetprop();
    let prefix = "";
    if(info.dir && info.dir !== ""){
      prefix = "export PATH=" + info.dir + ":$PATH; ";
    }
    return ksu.exec(prefix + cmd);
  }catch{return""}
}

function run(cmd,cb){
  const k=window.parent?.ksu||window.ksu;
  if(!k||!k.exec){popup("KSU not available","error");if(cb)cb("");return}

  const info = detectResetprop();
  let prefix = "";
  if(info.dir && info.dir !== ""){
    prefix = "export PATH=" + info.dir + ":$PATH; ";
  }
  const fullCmd = prefix + cmd;

  const id="c"+Date.now();
  let d=false;
  const t=setTimeout(()=>{if(d)return;d=true;delete(window.parent||window)[id];if(cb)cb("")},15000);
  (window.parent||window)[id]=function(){if(d)return;d=true;clearTimeout(t);delete(window.parent||window)[id];const r=arguments.length===1?arguments[0]:arguments[1]||"";if(cb)cb(r)};
  k.exec("sh -c '"+fullCmd.replace(/'/g,"'\\''")+"'","{}",id);
}

function log(msg,type){
  const panel=document.getElementById("logPanel");
  const content=document.getElementById("logContent");
  panel.style.display="block";
  const entry=document.createElement("div");
  entry.className="log-entry "+(type||"info");
  entry.textContent="["+new Date().toLocaleTimeString()+"] "+msg;
  content.appendChild(entry);
  content.scrollTop=content.scrollHeight;
  sh("mkdir -p "+DIR+"/Integrity-Box-Logs && echo '["+new Date().toISOString()+"] ["+(type||"INFO").toUpperCase()+"] "+msg.replace(/'/g,"'\''")+"' >> "+LOG_FILE);
}

function renderScripts(){
  const grid=document.getElementById("scriptGrid");
  grid.innerHTML="";
  scripts.forEach((s,i)=>{
    const btn=document.createElement("div");
    btn.className="script-btn"+(selected.has(i)?" on":"");
    btn.id="s"+i;
    btn.innerHTML=`<div>${s.name}</div>`;
    btn.onclick=()=>toggleScript(i);
    grid.appendChild(btn);
  });
}

function toggleScript(i){
  const el=document.getElementById("s"+i);
  if(selected.has(i)){
    selected.delete(i);
    el.classList.remove("on");
  }else{
    selected.add(i);
    el.classList.add("on");
  }
  savePrefs();
}

function savePrefs(){
  const arr=Array.from(selected).join(",");
  sh("echo '"+arr+"' > "+PREFS_FILE+"_scripts");
}

function loadPrefs(){
  const r=sh("cat "+PREFS_FILE+"_scripts 2>/dev/null || echo ''");
  const arr=String(r).trim().split(",").filter(x=>x!=="");
  arr.forEach(i=>{
    const n=parseInt(i);
    if(!isNaN(n)&&n>=0&&n<8)selected.add(n);
  });
}

function setProgress(current,total){
  document.getElementById("loaderText").textContent="Running "+current+" of "+total+" tasks...";
}

function executeScripts(){
  if(selected.size===0){popup("Select at least one option","error");return}
  execQueue=Array.from(selected).sort((a,b)=>a-b);
  execIdx=0;
  const total=execQueue.length;
  const btn=document.getElementById("execBtn");

  btn.disabled=true;
  showLoader(true,"Starting Beast Mode...");
  log("Beast Mode started","ok");

  function runNext(){
    if(execIdx>=total){
      setTimeout(()=>{
        showLoader(false);
        btn.disabled=false;
        popup("Beast Mode complete!","success");
        log("All tasks completed","ok");
      },400);
      return;
    }
    const s=scripts[execQueue[execIdx]];
    setProgress(execIdx+1,total);
    log("Running: "+s.name);
    run("sh "+s.path+" 2>&1",(result)=>{
      if(result&&result.trim())log(result.trim(),"info");
      execIdx++;
      popup(s.name+" completed","success");
      setTimeout(runNext,800);
    });
  }
  runNext();
}

function updateBankingUI(on){
  const badge=document.getElementById("bankingBadge");
  const input=document.getElementById("bankingInput");
  if(input)input.checked=on;
  if(badge){
    badge.textContent=on?"ON":"OFF";
    badge.className="status-badge "+(on?"on":"off");
  }
}

function checkBankingMode(){
  const r=sh("test -f "+BANKING_FLAG+" && echo 1 || echo 0");
  updateBankingUI(String(r).trim()==="1");
}

function toggleBankingMode(){
  if(bankingBusy)return;
  bankingBusy=true;

  const input=document.getElementById("bankingInput");
  const on=input.checked;

  showLoader(true,on?"Enabling Banking Mode...":"Disabling Banking Mode...");

  if(on){
    log("Enabling Banking Mode...");
    sh("settings put global sys_oem_unlock_allowed 0");
    sh("settings put global adb_enabled 0");
    sh("settings put global development_settings_enabled 0");
    sh("touch "+BANKING_FLAG);
    removeDex2oatFlags(()=>{
      showLoader(false);
      updateBankingUI(true);
      log("Banking Mode enabled","ok");
      popup("Banking Mode ON","success");
      bankingBusy=false;
    });
  }else{
    log("Disabling Banking Mode...");
    sh("settings put global sys_oem_unlock_allowed 1");
    sh("rm -f "+BANKING_FLAG);
    showLoader(false);
    updateBankingUI(false);
    log("Banking Mode disabled","info");
    popup("Banking Mode OFF","info");
    bankingBusy=false;
  }
}

function removeDex2oatFlags(cb){
  if(!cb){showLoader(true,"Checking Dex2OAT property...");log("Checking Dex2OAT property...");}
  const check=sh("getprop | grep -q '^\\[dalvik.vm.dex2oat-flags\\]' && echo EXISTS || echo NOT_FOUND");
  if(String(check).trim()==="NOT_FOUND"){
    if(cb){cb();return}
    showLoader(false);
    log("Property already clean","ok");
    popup("Cleaned","success");
    return;
  }
  const cmd = getResetpropDeleteCmd("dalvik.vm.dex2oat-flags", true);
  sh(cmd);
  if(cb){log("Auto-removed Dex2OAT flags","ok");cb();return}
  showLoader(false);
  log("Dex2OAT property removed","ok");
  popup("Dex2OAT removed","success");
}

document.addEventListener("DOMContentLoaded",()=>{
  loadPrefs();
  renderScripts();
  checkBankingMode();
});
