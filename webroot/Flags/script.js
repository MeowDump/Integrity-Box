var DIR="/data/adb/Box-Brain";
var ACTION_SCRIPT="/data/adb/modules/playintegrityfix/action.sh";

var BOOT_FLAGS=[
  {id:"spoof-los-boot",title:"Hide Lineage",label:"custom ROM",desc:"Spoofs LineageOS-specific properties on boot so apps cannot detect you are running a LineageOS-based custom ROM.",risk:"low"},
  {id:"nuke-los-boot",title:"Nuke Lineage",label:"custom ROM",desc:"Aggressively removes all LineageOS traces including props, services and build fingerprints on boot.",risk:"medium"},
  {id:"spoof-custom-rom-boot",title:"Hide Custom ROM",label:"custom ROM",desc:"Generic custom ROM hiding that spoofs build.props to appear as stock Android on boot.",risk:"low"},
  {id:"nuke-sus-boot",title:"Hide SUS Files",label:"root traces",desc:"Cleans suspicious files and directories that may reveal root access or module presence on boot.",risk:"medium"},
];

var REBOOT_FLAGS=[
  {id:"NoLineageProp",title:"Spoof Lineage Props",label:"reboot",desc:"Spoofs LineageOS build properties. Disable if camera or other hardware fails."},
  {id:"nodebug",title:"Debug Fingerprint",label:"reboot",desc:"Hides custom ROM debug fingerprint traces from app detection."},
  {id:"build",title:"Debug Build",label:"reboot",desc:"Spoofs build type from userdebug to user to appear as unmodified device."},
  {id:"tag",title:"Build Tag",label:"reboot",desc:"Spoofs build tags to release-keys instead of test-keys."},
  {id:"encrypt",title:"Spoof Encryption",label:"reboot",desc:"Fakes device encryption status to appear as encrypted"},
  {id:"twrp",title:"Hide Recovery",label:"reboot",desc:"Hides custom recovery presence by spoofing recovery path."},
  {id:"skip",title:"Skip System Patch",label:"reboot",desc:"Prevents spoofing of the security patch date. Use if banking apps detect patch mismatch. Disabling this can cause play integrity failure on old ROMs/Android versions"},
  {id:"spoof-selinux-boot",title:"Spoof SELinux",label:"bootloop risk",desc:"Spoofs SELinux status to report as enforcing. WARNING: May cause bootloops on some devices. Use with caution.",risk:"high"},
  {id:"hidehook",title:"Hide PIF Detection",label:"not recommended",desc:"Hides PIF-related hooks and detection traces on boot, it may automatically enable inbuilt ROM spoofing.",risk:"high"},
  {id:"safemode",title:"Safe Mode",label:"bootloop fix",desc:"Disables all extra spoofing features for maximum compatibility mode.",risk:"low"}
];

var ACTION_FLAGS=[
  {id:"lsposed",title:"Clear LSposed",label:"action",desc:"Removes LSposed framework traces from the system."},
  {id:"gapps",title:"Clear Gapps Logs",label:"action",desc:"Wipes Google Apps log files to avoid custom ROM detection."},
  {id:"root",title:"Clear Module Logs",label:"action",desc:"Wipes all module-related log files to clean detection traces."},
  {id:"ota",title:"OTA Fix",label:"action",desc:"Fixes LineageOS OTA update errors caused by spoofed properties."}
];

var GENERAL_FLAGS=[
  {id:"keymint",title:"Update OMK build",label:"reboot",desc:"Forces to appear as Pixel Device & use latest security patch if using Oh My Keymint module"},
  {id:"teesim",title:"Skip TEEsim",label:"reboot",desc:"This will skip modifications in config.json"},
  {id:"iframe_gesture_right",title:"Right Gestures",desc:"Enables right-hand-side back gesture swipe area in WebUI iframes."},
  {id:"iframe_back_button",title:"Floating Back",desc:"Adds a floating back button overlay for easier iframe navigation."},
  {id:"keyswitch",title:"DNS Poisoning:",desc:"This fixes keybox download errors in some regions"},
  {id:"noredirect",title:"No Redirect",desc:"Disables automatic Telegram link redirects from the WebUI."}
];

var KERNEL_FLAGS=[
  {id:"buildtime",title:"Spoof Build Time",label:"bootloop / soft brick risk",risk:"high",desc:"Fixed duck detector system & kernel build date mismatch detection"},
  {id:"customkernel",title:"Hide Custom Kernel",label:"bootloop / soft brick risk",risk:"high",desc:"Fixes custom kernel detection"},
  {id:"emoji",title:"No Gore",label:"bootloop / soft brick risk",risk:"high",desc:"Hides emojis & special characters from kernel string"},
  {id:"chinese",title:"Made in China",label:"bootloop / soft brick risk",risk:"high",desc:"Hides stuff written in chinese language to avoid detection."},
  {id:"telegram",title:"No Telegram",label:"bootloop / soft brick risk",risk:"high",desc:"Hides Telegram strings"},
  {id:"mention",title:"No Mention Tags",label:"bootloop / soft brick risk",risk:"high",desc:"Hides Mention strings"},
  {id:"cmdline",title:"Spoof CMDline",label:"bootloop / soft brick risk",risk:"high",desc:"spoofs CMDline"},
  {id:"board",title:"Spoof Kernel",label:"bootloop / soft brick risk",risk:"high",desc:"Hides Kernel name strings"},
  {id:"scanall",title:"All of Above",label:"bootloop / hard brick risk",risk:"high",desc:"Hides everything"}
];

var MESSAGES={
  noredirect:{on:"Redirect disabled",off:"Redirect enabled"},
  buildtime:{on:"Reboot your device",off:"Reboot your device"},
  customkernel:{on:"Reboot your device",off:"Reboot your device"},
  emoji:{on:"Reboot your device",off:"Reboot your device"},
  chinese:{on:"Reboot your device",off:"Reboot your device"},
  telegram:{on:"Reboot your device",off:"Reboot your device"},
  mention:{on:"Reboot your device",off:"Reboot your device"},
  cmdline:{on:"Reboot your device",off:"Reboot your device"},
  board:{on:"Reboot your device",off:"Reboot your device"},
  scanall:{on:"Reboot your device",off:"Reboot your device"},
  iframe_gesture_right:{on:"RHS gestures active",off:"RHS gestures disabled"},
  keyswitch:{on:"Using alternate fallback method",off:"Downloads will use default method"},
  iframe_back_button:{on:"Floating button active",off:"Floating button disabled"},
  safemode:{on:"Safe mode active",off:"Safe mode disabled"},
  twrp:{on:"Custom recovery spoofed",off:"Custom recovery disabled"},
  keymint:{on:"OMK Pixel disabled",off:"OMK Pixel enabled"},
  "spoof-selinux-boot":{on:"Please reboot your device",off:"Please reboot your device"},
  hidehook:{on:"Please reboot your device",off:"Please reboot your device"},
  encrypt:{on:"Encryption spoofed",off:"Encryption disabled"},
  lsposed:{on:"LSposed cleared",off:"LSposed disabled"},
  nodebug:{on:"Debug fingerprint spoofed",off:"Debug fingerprint disabled"},
  build:{on:"Debug build spoofed",off:"Debug build disabled"},
  skip:{on:"Reboot your device to apply changes",off:"Reboot your device to apply changes"},
  tag:{on:"Build tag spoofed",off:"Build tag disabled"},
  root:{on:"Module logs cleared",off:"Module logs disabled"},
  ota:{on:"OTA fix active",off:"OTA fix disabled"},
  NoLineageProp:{on:"Lineage props spoofed",off:"Lineage props unchanged"},
  gapps:{on:"Gapp logs cleared",off:"Gapp logs enabled"}
};

var actionExecEnabled=false;

function popup(msg,type){
  type=type||"info";
  try{
    if(typeof window.toast==="function"){window.toast(String(msg));return}
    if(window.kernelsu&&typeof window.kernelsu.toast==="function"){window.kernelsu.toast(String(msg));return}
    if(typeof ksu==="object"&&typeof ksu.toast==="function"){ksu.toast(String(msg));return}
  }catch(e){}

  var n=document.querySelector(".toast");
  if(!n){
    n=document.createElement("div");
    n.className="toast";
    document.body.appendChild(n);
  }
  n.textContent=msg;
  n.classList.add("show");
  clearTimeout(n._timer);
  n._timer=setTimeout(function(){n.classList.remove("show")},2500);
}

function runShell(cmd){
  return new Promise(function(resolve){
    if(window.parent&&window.parent.runShellFromIframe){
      window.parent.runShellFromIframe(cmd).then(function(r){resolve(r||"")}).catch(function(){resolve("")});
    }else{
      resolve("");
    }
  });
}

function getBadgeClass(risk){
  if(risk==="high")return"danger";
  if(risk==="medium")return"warn";
  return"";
}

function makeToggleRow(cfg,inputId,rowId,onclickFn,badgeClass,badgeText){
  var div=document.createElement("div");
  div.className="row-toggle";
  div.id=rowId;
  div.onclick=onclickFn;
  var badge="";
  if(badgeText)badge='<span class="badge '+(badgeClass||"")+'" id="badge-'+inputId+'">'+badgeText+'</span>';
  div.innerHTML=
    '<div class="title">'+
      '<span class="name">'+cfg.title+'</span>'+
      badge+
    '</div>'+
    '<label class="switch" onclick="event.stopPropagation()">'+
      '<input type="checkbox" id="'+inputId+'">'+
      '<span class="track"></span>'+
    '</label>';
  return div;
}

function createFlagRow(cfg,isBoot){
  var inputId=isBoot?"cb-boot-"+cfg.id:"cb-"+cfg.id;
  var rowId=isBoot?"row-boot-"+cfg.id:"row-"+cfg.id;
  var onclickFn=function(){isBoot?toggleBootFlag(cfg.id):toggle(cfg.id)};
  var badgeClass="";
  var badgeText=cfg.label;
  if(isBoot){
    badgeClass=getBadgeClass(cfg.risk);
  }
  return makeToggleRow(cfg,inputId,rowId,onclickFn,badgeClass,badgeText);
}

function createActionRow(cfg){
  return makeToggleRow(cfg,"cb-"+cfg.id,"row-"+cfg.id,function(){toggle(cfg.id)},"",cfg.label);
}

function createKernelRow(cfg){
  return makeToggleRow(cfg,"cb-"+cfg.id,"row-"+cfg.id,function(){toggle(cfg.id)},getBadgeClass(cfg.risk),cfg.label);
}

function createGeneralRow(cfg){
  return makeToggleRow(cfg,"cb-"+cfg.id,"row-"+cfg.id,function(){toggle(cfg.id)},"","");
}

async function toggleExec(){
  var row=document.getElementById("row-action_exec");
  var input=document.getElementById("cb-action_exec");
  if(row.classList.contains("spinning"))return;

  var newVal=!input.checked;
  input.checked=newVal;
  row.classList.toggle("active",newVal);
  actionExecEnabled=newVal;

  try{
    if(newVal){
      await runShell('touch "'+DIR+'/action_exec"');
      popup("Action execution enabled","success");
    }else{
      await runShell('rm -f "'+DIR+'/action_exec"');
      popup("Action execution disabled");
    }
  }catch(e){
    popup("Error: "+e.message,"error");
    input.checked=!newVal;
    row.classList.toggle("active",!newVal);
    actionExecEnabled=!newVal;
  }
}

async function toggle(id){
  var row=document.getElementById("row-"+id);
  var input=document.getElementById("cb-"+id);
  if(!input||row.classList.contains("spinning"))return;

  var newVal=!input.checked;
  input.checked=newVal;
  row.classList.toggle("active",newVal);

  var isAction=ACTION_FLAGS.some(function(a){return a.id===id});

  if(isAction&&newVal)row.classList.add("spinning");

  try{
    if(newVal){
      await runShell('touch "'+DIR+"/"+id+'"');
      if(isAction&&actionExecEnabled){
        popup("Executing action...","info");
        await runShell('sh "'+ACTION_SCRIPT+'"');
        var msg=(MESSAGES[id]&&MESSAGES[id].on?MESSAGES[id].on:id+" finished");
        popup(msg,"success");
      }else{
        var msg2=(MESSAGES[id]&&MESSAGES[id].on?MESSAGES[id].on:"Enabled");
        popup(msg2,"success");
      }
    }else{
      await runShell('rm -f "'+DIR+"/"+id+'"');
      var msg3=(MESSAGES[id]&&MESSAGES[id].off?MESSAGES[id].off:"Disabled");
      popup(msg3);
    }
  }catch(e){
    popup("Error: "+e.message,"error");
    input.checked=!newVal;
    row.classList.toggle("active",!newVal);
  }finally{
    row.classList.remove("spinning");
  }
}

async function toggleBootFlag(id){
  var row=document.getElementById("row-boot-"+id);
  var input=document.getElementById("cb-boot-"+id);
  if(!input||row.classList.contains("spinning"))return;

  var newVal=!input.checked;
  input.checked=newVal;
  row.classList.toggle("active",newVal);

  var flagPath=DIR+"/"+id;

  try{
    if(newVal){
      await runShell('mkdir -p "'+DIR+'"');
      await runShell('touch "'+flagPath+'"');
      var verify=await runShell('test -f "'+flagPath+'" && echo EXISTS || echo MISSING');
      if(String(verify).trim()==="EXISTS"){
        popup(id+" enabled  Reboot required","success");
        showRebootHint();
      }else{
        popup(id+" failed to create","error");
        input.checked=false;
        row.classList.remove("active");
      }
    }else{
      await runShell('rm -f "'+flagPath+'"');
      var verify=await runShell('test -f "'+flagPath+'" && echo EXISTS || echo MISSING');
      if(String(verify).trim()==="MISSING"){
        popup(id+" disabled  Reboot required","info");
        showRebootHint();
      }else{
        popup(id+" failed to remove","error");
        input.checked=true;
        row.classList.add("active");
      }
    }
  }catch(e){
    popup("Error: "+e.message,"error");
    input.checked=!newVal;
    row.classList.toggle("active",!newVal);
  }
}

function showRebootHint(){
  var hint=document.getElementById("rebootHint");
  hint.classList.add("show");
}

function openInfoModal(){
  var modal=document.getElementById("infoModal");
  var content=document.getElementById("infoContent");
  if(!content.innerHTML){
    var sections=[
      {title:"Boot Flags",items:BOOT_FLAGS,showRisk:true},
      {title:"Reboot Flags",items:REBOOT_FLAGS,showRisk:false},
      {title:"Action Flags",items:ACTION_FLAGS,showRisk:false},
      {title:"Kernel",items:KERNEL_FLAGS,showRisk:true},
      {title:"General",items:GENERAL_FLAGS,showRisk:false}
    ];

    sections.forEach(function(sec){
      var sectionTitle=document.createElement("div");
      sectionTitle.className="info-section-title";
      sectionTitle.textContent=sec.title;
      content.appendChild(sectionTitle);

      sec.items.forEach(function(item){
        var div=document.createElement("div");
        div.className="info-item";
        var riskHtml="";
        if(sec.showRisk&&item.risk){
          var riskColor=item.risk==="high"?"var(--err)":item.risk==="medium"?"var(--warn)":"var(--ok)";
          var riskText=item.risk==="high"?"High Risk":item.risk==="medium"?"Medium Risk":"Low Risk";
          riskHtml='<div class="info-item-risk" style="color:'+riskColor+'">'+riskText+'</div>';
        }
        div.innerHTML='<div class="info-item-title">'+item.title+'</div><div class="info-item-desc">'+item.desc+'</div><div class="info-item-flag">Flag: '+item.id+'</div>'+riskHtml;
        content.appendChild(div);
      });
    });
  }
  modal.classList.add("show");
}

function closeInfoModal(e){
  if(e&&e.target!==e.currentTarget)return;
  var modal=document.getElementById("infoModal");
  modal.classList.remove("show");
}

function buildCheckCmd(arr,type){
  if(!arr.length)return'echo ""';
  var ids=arr.map(function(b){return b.id}).join(" ");
  return'for f in '+ids+';do if [ -f "'+DIR+'/$f" ];then echo "'+type+':$f:1";else echo "'+type+':$f:0";fi;done';
}

async function refreshAll(){
  var bootCmd=buildCheckCmd(BOOT_FLAGS,"boot");
  var rebootCmd=buildCheckCmd(REBOOT_FLAGS,"reboot");
  var actionCmd=buildCheckCmd(ACTION_FLAGS,"action");
  var kernelCmd=buildCheckCmd(KERNEL_FLAGS,"kernel");
  var generalCmd=buildCheckCmd(GENERAL_FLAGS,"general");
  var execCmd='if [ -f "'+DIR+'/action_exec" ];then echo "exec:action_exec:1";else echo "exec:action_exec:0";fi';

  var result=await runShell(bootCmd+";"+rebootCmd+";"+actionCmd+";"+kernelCmd+";"+generalCmd+";"+execCmd);

  if(result){
    result.trim().split("\n").forEach(function(line){
      var parts=line.split(":");
      if(parts.length!==3)return;
      var type=parts[0].trim();
      var id=parts[1].trim();
      var val=parts[2].trim();

      if(type==="boot"){
        var cb=document.getElementById("cb-boot-"+id);
        var row=document.getElementById("row-boot-"+id);
        if(cb&&row){
          cb.checked=val==="1";
          row.classList.toggle("active",val==="1");
        }
      }else if(type==="reboot"||type==="action"||type==="kernel"||type==="general"){
        var cb2=document.getElementById("cb-"+id);
        var row2=document.getElementById("row-"+id);
        if(cb2&&row2){
          cb2.checked=val==="1";
          row2.classList.toggle("active",val==="1");
        }
      }else if(type==="exec"&&id==="action_exec"){
        var cb3=document.getElementById("cb-action_exec");
        var row3=document.getElementById("row-action_exec");
        if(cb3&&row3){
          cb3.checked=val==="1";
          row3.classList.toggle("active",val==="1");
          actionExecEnabled=val==="1";
        }
      }
    });
  }
  popup("States refreshed","info");
}

function init(){
  var flagContainer=document.getElementById("flag-rows");
  var actionContainer=document.getElementById("action-rows");
  var kernelContainer=document.getElementById("kernel-rows");
  var generalContainer=document.getElementById("general-rows");

  BOOT_FLAGS.forEach(function(b){flagContainer.appendChild(createFlagRow(b,true))});
  REBOOT_FLAGS.forEach(function(b){flagContainer.appendChild(createFlagRow(b,false))});
  ACTION_FLAGS.forEach(function(a){actionContainer.appendChild(createActionRow(a))});
  KERNEL_FLAGS.forEach(function(g){kernelContainer.appendChild(createKernelRow(g))});
  GENERAL_FLAGS.forEach(function(g){generalContainer.appendChild(createGeneralRow(g))});

  setTimeout(refreshAll,50);
}

document.addEventListener("DOMContentLoaded",init);
