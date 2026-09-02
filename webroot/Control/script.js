const DIR="/data/adb/Box-Brain";
const PROP="/data/adb/modules/playintegrityfix/custom.pif.prop";
const MOD_PROP="/data/adb/modules/playintegrityfix/module.prop";
const STABLE_URL="https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/release.json";
const BETA_URL="https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/beta-release/ota.json";
const ZYGISK_DIR="/data/adb/zygisksu";
const STYLE_SCRIPT="/data/adb/modules/playintegrityfix/webroot/common_scripts/UI/style.sh";

function popup(msg, type) {
  if(!type) type="info";
  try {
    if (typeof window.toast === "function") { window.toast(String(msg)); return; }
    if (window.kernelsu && typeof window.kernelsu.toast === "function") { window.kernelsu.toast(String(msg)); return; }
    if (typeof ksu === "object" && typeof ksu.toast === "function") { ksu.toast(String(msg)); return; }
  } catch(e){}

  let n = document.querySelector(".toast");
  if (!n) {
    n = document.createElement("div");
    n.className = "toast";
    document.body.appendChild(n);
  }
  n.textContent = msg;
  n.classList.add("show");
  clearTimeout(n._timer);
  n._timer = setTimeout(function(){ n.classList.remove("show"); }, 2500);
}

function run(cmd,cb){
  var k=window.parent?window.parent.ksu:null;
  if(!k) k=window.ksu;
  if(!k||!k.exec){popup("KSU not available","error");if(cb)cb("");return}
  var id="c"+Date.now();
  var d=false;
  var t=setTimeout(function(){if(d)return;d=true;delete(window.parent||window)[id];if(cb)cb("")},3000);
  (window.parent||window)[id]=function(){if(d)return;d=true;clearTimeout(t);delete(window.parent||window)[id];var r=arguments.length===1?arguments[0]:arguments[1]||"";if(cb)cb(r)};
  k.exec("sh -c '"+cmd.replace(/'/g,"'\\''")+"'","{}",id);
}

function touch(path,on){if(on)run("mkdir -p "+DIR+" && touch "+path,function(){});else run("rm -f "+path,function(){});}
function write(key,val,cb){
  run(
    "mkdir -p $(dirname "+PROP+") && touch "+PROP+" && " +
    "if grep -q '^"+key+"=' "+PROP+"; then " +
    "sed -i 's/^"+key+"=.*/"+key+"="+val+"/' "+PROP+"; " +
    "else " +
    "printf '\\n"+key+"="+val+"\\n' >> "+PROP+"; " +
    "fi",
    cb
  );
}

function setOn(id,on){
  var el=document.getElementById(id);
  el.classList.toggle("on",on);
  var input=el.querySelector('input[type="checkbox"]');
  if(input)input.checked=on;
}

function toggle(name){
  var el=document.getElementById(name);
  var on=!el.classList.contains("on");
  touch(DIR+"/"+name,on);
  setOn(name,on);
  popup((on?"Enabled ":"Disabled ")+name,"success");
}

function toggleProp(key){
  var el=document.getElementById(key==="verboseLogs"?"verbose":"");
  var on=!el.classList.contains("on");
  write(key,on?"1":"0",function(){
    setOn(key==="verboseLogs"?"verbose":"",on);
    popup((on?"Enabled ":"Disabled ")+key,"success");
  });
}

function toggleLite(){
  var el=document.getElementById("lite");
  var on=!el.classList.contains("on");

  write("spoofApps", on ? "0" : "1", function() {
    touch(DIR+"/autopilot", on);

    setOn("lite", on);

    popup(on ? "Lite Mode on" : "Lite Mode off", "success");
  });
}

function toggleZygiskNext(){
  var el=document.getElementById("zygisknext");
  var on=!el.classList.contains("on");
  if(on){
    run(
      "mkdir -p "+ZYGISK_DIR+" && " +
      "echo '2' > "+ZYGISK_DIR+"/denylist_enforce && " +
      "echo '1' > "+ZYGISK_DIR+"/memory_type && " +
      "echo '1' > "+ZYGISK_DIR+"/linker && " +
      "echo '0' > "+ZYGISK_DIR+"/klog",
      function(){
        setOn("zygisknext",true);
        popup("Zygisk Next configured","success");
      }
    );
  }else{
    run(
      "mkdir -p "+ZYGISK_DIR+" && " +
      "echo '0' > "+ZYGISK_DIR+"/denylist_enforce && " +
      "echo '0' > "+ZYGISK_DIR+"/memory_type && " +
      "echo '0' > "+ZYGISK_DIR+"/linker && " +
      "echo '0' > "+ZYGISK_DIR+"/klog",
      function(){
        setOn("zygisknext",false);
        popup("Zygisk Next reset to defaults","success");
      }
    );
  }
}

function updateCanary(){
  run("sh /data/adb/modules/playintegrityfix/webroot/UpdateTranslation.sh", function(r){
    popup("Canary updated","success");
  });
}

function setMode(v){
  [3,6,9].forEach(function(x){touch(DIR+"/top_"+x,false);touch(DIR+"/depth_"+x,false)});
  touch(DIR+"/top_"+v,true);
  touch(DIR+"/depth_"+v,true);
  [3,6,9].forEach(function(x){setOn("m"+x,x===v)});
  popup(v===3?"Basic mode":v===6?"Normal mode":"Extreme mode","success");
}

function setUpdateUrl(url,cb){
  run(
    "if grep -q '^updateJson=' "+MOD_PROP+"; then " +
    "sed -i 's|^updateJson=.*|updateJson="+url+"|' "+MOD_PROP+"; " +
    "else " +
    "printf '\\nupdateJson="+url+"\\n' >> "+MOD_PROP+"; " +
    "fi",
    cb
  );
}

function updateBetaUI(isBeta){
  var el=document.getElementById("beta");
  el.classList.toggle("on",isBeta);
  document.getElementById("betaInput").checked=isBeta;
  document.getElementById("labelStable").classList.toggle("active-label",!isBeta);
  document.getElementById("labelBeta").classList.toggle("active-label",isBeta);
}

function toggleBeta(){
  var el=document.getElementById("beta");
  var isBeta=!el.classList.contains("on");
  var url=isBeta?BETA_URL:STABLE_URL;
  setUpdateUrl(url,function(){
    updateBetaUI(isBeta);
    popup(isBeta?"Switched to Beta channel":"Switched to Stable channel","success");
  });
}

function updateUiModeUI(isModern){
  var el=document.getElementById("uiMode");
  el.classList.toggle("on",isModern);
  document.getElementById("uiModeInput").checked=isModern;
  document.getElementById("labelClassic").classList.toggle("active-label",!isModern);
  document.getElementById("labelModern").classList.toggle("active-label",isModern);
}

function toggleUiMode(){
  var el=document.getElementById("uiMode");
  var isModern=!el.classList.contains("on");
  var cmd="mkdir -p "+DIR+" && ";
  if(isModern){
    cmd+="rm -f "+DIR+"/classic && touch "+DIR+"/modern";
  }else{
    cmd+="rm -f "+DIR+"/modern && touch "+DIR+"/classic";
  }
  cmd+=" && sh "+STYLE_SCRIPT;
  run(cmd,function(){
    updateUiModeUI(isModern);
    popup(isModern?"Switched to Modern UI":"Switched to Classic UI","success");
  });
}

function openHelp(){
  document.getElementById("helpModal").classList.add("show");
}

function closeHelp(){
  document.getElementById("helpModal").classList.remove("show");
}

function closeHelpOnBackdrop(e){
  if(e.target===e.currentTarget) closeHelp();
}

function init(){
  var cmd =
    "DIR='"+DIR+"'; " +
    "PROP='"+PROP+"'; " +
    "MOD_PROP='"+MOD_PROP+"'; " +
    "ZYGISK_DIR='"+ZYGISK_DIR+"'; " +
    "check(){ [ -f \"$1\" ] && echo 1 || echo 0; }; " +
    "printf '{\"zygisk\":\"%s\",\"keybox\":\"%s\",\"json\":\"%s\",\"verbose\":\"%s\",\"spoofApps\":\"%s\",\"autopilot\":\"%s\",\"updateUrl\":\"%s\",\"modern\":\"%s\",\"top3\":\"%s\",\"top6\":\"%s\",\"top9\":\"%s\",\"zn_mem\":\"%s\",\"zn_link\":\"%s\",\"zn_klog\":\"%s\",\"zn_deny\":\"%s\"}\\n' " +
    "\"$(check $DIR/zygisk)\" " +
    "\"$(check $DIR/keybox)\" " +
    "\"$(check $DIR/json)\" " +
    "\"$(grep -m1 '^verboseLogs=' $PROP | cut -d= -f2- | tr -d '\\n' || echo '')\" " +
    "\"$(grep -m1 '^spoofApps=' $PROP | cut -d= -f2- | tr -d '\\n' || echo '')\" " +
    "\"$(check $DIR/autopilot)\" " +
    "\"$(grep -m1 '^updateJson=' $MOD_PROP | cut -d= -f2- | tr -d '\\n' || echo '')\" " +
    "\"$(check $DIR/modern)\" " +
    "\"$(check $DIR/top_3)\" " +
    "\"$(check $DIR/top_6)\" " +
    "\"$(check $DIR/top_9)\" " +
    "\"$(cat $ZYGISK_DIR/memory_type 2>/dev/null | tr -d '\\n' || echo '')\" " +
    "\"$(cat $ZYGISK_DIR/linker 2>/dev/null | tr -d '\\n' || echo '')\" " +
    "\"$(cat $ZYGISK_DIR/klog 2>/dev/null | tr -d '\\n' || echo '')\" " +
    "\"$(cat $ZYGISK_DIR/denylist_enforce 2>/dev/null | tr -d '\\n' || echo '')\"";

  run(cmd, function(r){
    var d;
    try { d = JSON.parse(r.trim()); } catch(e) { return; }

    setOn("zygisk", d.zygisk === "1");
    setOn("keybox", d.keybox === "1");
    setOn("json", d.json === "1");
    setOn("verbose", d.verbose === "1");

    var spoofDisabled = d.spoofApps === "0";
    var autopilotEnabled = d.autopilot === "1";
    setOn("lite", spoofDisabled && autopilotEnabled);

    updateBetaUI(d.updateUrl === BETA_URL);
    updateUiModeUI(d.modern === "1");

    var a = 3;
    if(d.top9 === "1") a = 9;
    else if(d.top6 === "1") a = 6;
    else if(d.top3 === "1") a = 3;
    setMode(a);

    var znOn = d.zn_mem === "1" && d.zn_link === "1" && d.zn_klog === "0" && d.zn_deny === "2";
    setOn("zygisknext", znOn);
  });
}

document.addEventListener("DOMContentLoaded",init);
