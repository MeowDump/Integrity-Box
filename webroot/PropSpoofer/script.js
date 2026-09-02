const coreCount=document.getElementById('coreCount');
const coreLabel=document.getElementById('coreLabel');
const coreSub=document.getElementById('coreSub');
const fixBtn=document.getElementById('fixBtn');
const fixLabel=document.getElementById('fixLabel');
const statusPill=document.getElementById('statusPill');
const statusText=document.getElementById('statusText');

const modalCats={reset:false,duck:false,pif:false,detection:false,romhide:false};
let detectedProps=[];
let hasKsu=false;
let tT=null;
const LOG_DIR='/data/adb/Box-Brain/Integrity-Box-Logs';
const LOG_FILE=LOG_DIR+'/PropSpoofer.log';

const resetCmds=[
'su -c resetprop -n sys.usb.adb.disabled 1',
'su -c resetprop -n persist.sys.usb.config mtp; su -c resetprop -n sys.usb.config mtp; su -c resetprop -n sys.usb.state mtp',
'su -c resetprop -n service.adb.root 0; su -c resetprop -n service.adb.tcp.port -1',
'su -c resetprop -n ro.secure 1; su -c resetprop -n ro.adb.secure 1',
'su -c resetprop -n ro.debuggable 0; su -c resetprop -n persist.sys.debuggable 0',
'su -c resetprop -n persist.sys.developer_options 0; su -c resetprop -n persist.sys.dev_mode 0',
'su -c resetprop -n ro.boot.verifiedbootstate green; su -c resetprop -n vendor.boot.verifiedbootstate green',
'su -c resetprop -n ro.boot.flash.locked 1',
'su -c resetprop -n ro.boot.vbmeta.device_state locked; su -c resetprop -n vendor.boot.vbmeta.device_state locked',
'su -c resetprop -n ro.secureboot.lockstate locked',
'su -c resetprop -n ro.boot.warranty_bit 0',
'su -c resetprop -n ro.build.type user; su -c resetprop -n ro.build.tags release-keys',
'su -c resetprop -n ro.oem_unlock_supported 0; su -c resetprop -n sys.oem_unlock_allowed 0',
'su -c resetprop -n ro.kernel.qemu 0; su -c resetprop -n ro.boot.qemu 0; su -c resetprop -n ro.hardware.virtual_device 0',
'find /data/app -type f \\( -name "*.odex" -o -name "*.vdex" \\) -delete 2>/dev/null; find /data/app -type f -name "base.odex" -delete 2>/dev/null'
];

const duckList=[
{prop:'ro.adb.secure',label:'ADB Secure'},
{prop:'ro.boot.verifiedbootstate',label:'Verified Boot State'},
{prop:'ro.boot.veritymode',label:'Verity Mode'},
{prop:'ro.build.tags',label:'Build Tags'},
{prop:'ro.build.type',label:'Build Type'}
];

const pifList=[
'sys.eliteprops.pif','ro.pixel.device','ro.pixel.version',
'ro.pixel.build.version','ro.pixel.releasetype','ro.pixellegal.url',
'sys.eliteprops.pixelprops','sys.eliteprops.vending','sys.eliteprops.keybox'
];

const deleteProps=[
{prop:'ro.lineage.device',label:'Lineage Device'},
{prop:'ro.crdroid.device',label:'crDroid Device'},
{prop:'ro.build.flavor',label:'Build Flavor'},
{prop:'ro.custom.device',label:'Custom Device'},
{prop:'ro.build.elitever',label:'Elite Version'},
{prop:'ro.xiaomi.developerid',label:'Xiaomi Dev ID'},
{prop:'ro.modversion',label:'Mod Version'},
{prop:'ro.elite.version.code_time',label:'Elite Time'},
{prop:'sys.eliteprops.keybox',label:'Elite Keybox'},
{prop:'sys.eliteprops.pif',label:'Elite PIF'},
{prop:'sys.eliteprops.vending',label:'Elite Vending'},
{prop:'sys.eliteprops.pixelprops',label:'Elite Pixel'},
{prop:'sys.eliteprops.photos',label:'Elite Photos'},
{prop:'sys.eliteprops.games',label:'Elite Games'},
{prop:'sys.eliteprops.snapchat',label:'Elite Snapchat'},
{prop:'sys.eliteprops.recent',label:'Elite Recent'},
{prop:'sys.eliteprops.recent.all',label:'Elite Recent All'},
{prop:'sys.eliteprops.spoofastab',label:'Elite Spoof'},
{prop:'ro.pixel.device',label:'Pixel Device'},
{prop:'ro.pixel.version',label:'Pixel Version'},
{prop:'ro.pixel.build.version',label:'Pixel Build'},
{prop:'ro.pixel.releasetype',label:'Pixel Release'},
{prop:'ro.pixellegal.url',label:'Pixel Legal'},
{prop:'ro.evolution.device',label:'Evolution Device'},
{prop:'ro.evolution.build.version',label:'Evolution Build'},
{prop:'ro.evolution.display.version',label:'Evolution Display'},
{prop:'ro.evolution.version',label:'Evolution Version'},
{prop:'ro.evolutionlegal.url',label:'Evolution Legal'},
{prop:'ro.lineage.build.version.plat.sdk',label:'Lineage SDK'},
{prop:'ro.lineage.build.version.plat.rev',label:'Lineage Rev'},
{prop:'ro.rising.feature.pop_up_view',label:'Rising Popup'},
{prop:'ro.rising.chipset',label:'Rising Chipset'},
{prop:'ro.rising.maintainer',label:'Rising Maintainer'},
{prop:'ro.rising.code',label:'Rising Code'},
{prop:'ro.rising.packagetype',label:'Rising Package'},
{prop:'ro.rising.releasetype',label:'Rising Release'},
{prop:'ro.rising.version',label:'Rising Version'},
{prop:'ro.rising.build.version',label:'Rising Build'},
{prop:'ro.rising.display.version',label:'Rising Display'},
{prop:'ro.rising.platform_release_codename',label:'Rising Codename'},
{prop:'ro.rising.device',label:'Rising Device'},
{prop:'ro.rising.storage',label:'Rising Storage'},
{prop:'ro.rising.ram',label:'Rising RAM'},
{prop:'ro.rising.battery',label:'Rising Battery'},
{prop:'ro.rising.display_resolution',label:'Rising Resolution'},
{prop:'ro.lineage.version',label:'Lineage Version'},
{prop:'ro.lineage.display.version',label:'Lineage Display'},
{prop:'ro.lineage.build.version',label:'Lineage Build'},
{prop:'ro.lineage.releasetype',label:'Lineage Release'},
{prop:'ro.lineagelegal.url',label:'Lineage Legal'},
{prop:'ro.infinity.device',label:'Infinity Device'},
{prop:'sys.lineage_settings_secure_version',label:'Lineage Secure'},
{prop:'sys.lineage_settings_system_version',label:'Lineage Sys'},
{prop:'ro.infinity.soc',label:'Infinity SoC'},
{prop:'ro.infinity.battery',label:'Infinity Battery'},
{prop:'ro.infinity.display',label:'Infinity Display'},
{prop:'ro.infinity.camera',label:'Infinity Camera'},
{prop:'ro.infinity.android.version',label:'Infinity Android'},
{prop:'ro.infinity.build.version',label:'Infinity Build'},
{prop:'ro.infinity.build.status',label:'Infinity Status'},
{prop:'ro.infinity.build.date',label:'Infinity Date'},
{prop:'ro.infinity.buildtype',label:'Infinity Type'},
{prop:'ro.infinity.fingerprint',label:'Infinity Fingerprint'},
{prop:'ro.infinity.version',label:'Infinity Version'},
{prop:'ro.infinity.maintainer',label:'Infinity Maintainer'},
{prop:'ro.havoc.build.variant',label:'Havoc Variant'},
{prop:'ro.havoc.device',label:'Havoc Device'},
{prop:'ro.havoc.build.date',label:'Havoc Date'},
{prop:'ro.havoc.build.version',label:'Havoc Build'},
{prop:'ro.havoc.fingerprint',label:'Havoc Fingerprint'},
{prop:'ro.havoc.releasetype',label:'Havoc Release'},
{prop:'ro.havoc.version',label:'Havoc Version'},
{prop:'ro.havoc.build.version.security_patch',label:'Havoc Security'},
{prop:'ro.derpfest.device',label:'Derpfest Device'},
{prop:'ro.derpfest.build.date',label:'Derpfest Date'},
{prop:'ro.derpfest.build.version',label:'Derpfest Build'},
{prop:'ro.derpfest.build.variant',label:'Derpfest Variant'},
{prop:'ro.derpfest.display.version',label:'Derpfest Display'},
{prop:'ro.derpfest.releasetype',label:'Derpfest Release'},
{prop:'ro.derpfest.version',label:'Derpfest Version'},
{prop:'ro.derpfestlegal.url',label:'Derpfest Legal'},
{prop:'ro.axion.device',label:'Axion Device'},
{prop:'ro.axion.version',label:'Axion Version'},
{prop:'ro.axion.display.version',label:'Axion Display'},
{prop:'ro.axion.build.version',label:'Axion Build'},
{prop:'ro.axion.releasetype',label:'Axion Release'},
{prop:'persist.sys.axion_maintainer',label:'Axion Maintainer'},
{prop:'persist.sys.axion_processor_info',label:'Axion Processor'}
];

const romKeywords='lineage|evolution|crdroid|arrow|mistos|axion|infinity|pixelos|rising|lunaris|halcyon|havoc|alphadroid|avium|bliss|calyx|derpfest|graphene|lmodroid|lumine|matrixx|sakura|statix|superior|clover|witaqua|yaap|mica';

function getApi(){
if(window.parent&&window.parent!==window&&typeof window.parent.runShellFromIframe==='function'){
return {type:'iframe',exec:window.parent.runShellFromIframe};
}
const k=(typeof ksu!=='undefined'&&ksu.exec)?ksu:(window.parent&&window.parent.ksu)?window.parent.ksu:null;
if(k&&typeof k.exec==='function')return {type:'ksu',exec:k.exec.bind(k)};
return null;
}

async function sh(cmd,timeoutMs){
timeoutMs=timeoutMs||12000;
const api=getApi();
if(!api)throw new Error('KSU');
if(api.type==='iframe'){
const r=await Promise.race([
api.exec(cmd),
new Promise((_,rej)=>setTimeout(()=>rej(new Error('TIMEOUT')),timeoutMs))
]);
return (r||'').replace(/\r/g,'');
}
return new Promise((res,rej)=>{
const timer=setTimeout(()=>rej(new Error('TIMEOUT')),timeoutMs);
const cb='c'+Date.now()+(Math.random()*1e4|0);
window[cb]=(c,o,e)=>{
clearTimeout(timer);
delete window[cb];
if(c===0){res((o||'').replace(/\r/g,''));}
else{rej(new Error(e||o||'exit:'+c));}
};
try{api.exec(cmd,'{}',cb);}catch(ex){clearTimeout(timer);delete window[cb];rej(ex);}
});
}

async function safeSh(cmd,timeoutMs){
try{return await sh(cmd,timeoutMs);}catch(e){return '';}
}

function writeLog(line){
const safe=line.replace(/'/g,"'\\''").replace(/`/g,'\\`');
const ts=new Date().toISOString().replace('T',' ').substring(0,19);
safeSh("printf '%s\\n' '"+ts+" | "+safe+"' >> "+LOG_FILE).catch(()=>{});
}

function log(line){writeLog(line);}

function toast(msg,type){
try{
if(typeof window.toast==='function'){window.toast(String(msg));return;}
if(window.kernelsu&&typeof window.kernelsu.toast==='function'){window.kernelsu.toast(String(msg));return;}
if(typeof ksu==='object'&&typeof ksu.toast==='function'){ksu.toast(String(msg));return;}
}catch(e){}
let el=document.getElementById('toast');
if(!el){
el=document.createElement('div');
el.id='toast';
el.className='toast';
document.body.appendChild(el);
}
el.textContent=msg;
el.classList.add('show');
if(tT)clearTimeout(tT);
tT=setTimeout(()=>el.classList.remove('show'),3200);
}

async function exists(p){
try{return (await sh('getprop '+p+' 2>/dev/null',5000)).trim()!=='';}catch{return false;}
}

function showErrorState(msg){
coreCount.textContent='0';
coreLabel.textContent='ERROR';
coreSub.textContent=msg||'Scan failed';
statusText.textContent='Scan failed';
statusPill.className='chip chip-err';
fixBtn.disabled=true;
toast(msg||'Scan failed','err');
}

function showAllClear(){
coreCount.textContent='0';
coreLabel.textContent='EVERYTHING IS SPOOFED';
coreSub.textContent='No detectable props found on this device';
statusText.textContent='All clear';
statusPill.className='chip chip-ok';
fixBtn.disabled=true;
fixLabel.textContent='All Clear';
log('Auto-scan complete. Zero detections. All clear.');
}

function showScanComplete(count){
detectedProps=found;
coreCount.textContent=count;
coreLabel.textContent='SCAN COMPLETE';
coreSub.textContent=count+' detection props found on device';
fixBtn.disabled=false;
fixLabel.textContent='Fix Detection';
statusText.textContent='Scan complete';
statusPill.className='chip chip-ok';
log('Auto-scan complete. Total found: '+count);
setTimeout(()=>openModal(),700);
}

let found=[];

async function autoScan(){
found=[];
log('=== AUTO-SCAN STARTED ===');
coreLabel.textContent='SCANNING DEVICE';
coreSub.textContent='Initializing scan...';
coreCount.textContent='0';
statusText.textContent='Scanning device';
statusPill.className='chip chip-muted';

try{
await safeSh('mkdir -p '+LOG_DIR);
await safeSh("printf '%s\\n' '--- PropSpoofer Log ---' > "+LOG_FILE);
log('Log initialized at '+LOG_FILE);
}catch(e){
log('Log init warning');
}

try{
coreSub.textContent='Reading system properties...';
const allPropsOut=await sh('getprop',8000);
const allLines=allPropsOut.split('\n');
const propMap=new Map();

for(const line of allLines){
const m=line.match(/^\[([^\]]+)\]:\s*\[(.*)\]$/);
if(m)propMap.set(m[1],m[2]);
}

coreSub.textContent='Checking known ROM props...';

for(const p of deleteProps){
if(propMap.has(p.prop)){
found.push({prop:p.prop,label:p.label,category:'rom'});
log('[FOUND] '+p.prop+' (rom)');
}
}

for(const p of duckList){
if(propMap.has(p.prop)){
found.push({prop:p.prop,label:p.label,category:'duck'});
log('[FOUND] '+p.prop+' (duck)');
}
}

coreSub.textContent='Scanning hook props...';
const hookOut=await safeSh('getprop | grep -E "pphooks|pihook|pixelprops" | sed -E "s/^\\[(.*)\\]:.*/\\1/" 2>/dev/null || true',8000);
const bad=['dalvik','init.svc','debug_pid','appimageformat','zygote','persist.sys'];
const hookLines=hookOut.trim().split('\n').filter(l=>l.trim() && !bad.some(b=>l.includes(b)));
for(const prop of hookLines){
found.push({prop:prop,label:prop,category:'hook'});
log('[FOUND] '+prop+' (hook)');
}

coreSub.textContent='Scanning ROM keywords...';
const romOut=await safeSh('getprop | sed "s/^\\[//; s/\\]:.*//" | grep -i -E "('+romKeywords+')" 2>/dev/null || true',8000);
const romLines=romOut.trim().split('\n').filter(l=>l.trim());
for(const prop of romLines){
const already=found.some(x=>x.prop===prop);
if(!already){
found.push({prop:prop,label:prop,category:'rom'});
log('[FOUND] '+prop+' (rom-keyword)');
}
}

detectedProps=found;
coreCount.textContent=found.length;

if(found.length===0){
showAllClear();
return;
}

showScanComplete(found.length);

}catch(e){
log('Scan error: '+(e.message||''));
showErrorState(e.message==='TIMEOUT'?'Scan timed out. Try again.':'Scan failed: '+(e.message||''));
}
}

function openModal(){
document.getElementById('modal').classList.add('open');
modalCats.reset=false;
modalCats.duck=false;
modalCats.pif=false;
modalCats.detection=true;
modalCats.romhide=false;

document.getElementById('m-reset').classList.remove('on');
document.getElementById('m-duck').classList.remove('on');
document.getElementById('m-pif').classList.remove('on');
document.getElementById('m-detection').classList.add('on');
document.getElementById('m-romhide').classList.remove('on');

updateProceedBtn();
}

function closeModal(){
document.getElementById('modal').classList.remove('open');
}

function openInfoSheet(){
document.getElementById('infoSheet').classList.add('open');
}

function closeInfoSheet(){
document.getElementById('infoSheet').classList.remove('open');
}

function openPifWarning(){
document.getElementById('pifWarning').classList.add('open');
}

function closePifWarning(){
document.getElementById('pifWarning').classList.remove('open');
}

function toggleModalOpt(cat){
modalCats[cat]=!modalCats[cat];
document.getElementById('m-'+cat).classList.toggle('on',modalCats[cat]);
if(cat==='pif'&&modalCats.pif){
openPifWarning();
}
updateProceedBtn();
}

function updateProceedBtn(){
const any=modalCats.reset||modalCats.duck||modalCats.pif||modalCats.detection||modalCats.romhide;
document.getElementById('proceedBtn').disabled=!any;
}

async function proceed(){
if(!modalCats.reset&&!modalCats.duck&&!modalCats.pif&&!modalCats.detection&&!modalCats.romhide){
toast('Select at least one option','err');
return;
}
closeModal();
fixBtn.disabled=true;
fixBtn.classList.add('loading');
fixLabel.textContent='Processing...';
statusText.textContent='Applying fixes';
statusPill.className='chip chip-muted';

log('=== EXECUTION STARTED ===');
const startTime=Date.now();

const jobs=[];

if(modalCats.reset){
jobs.push((async()=>{
log('Category: Reset Props');
for(const c of resetCmds){
try{
await sh(c);
log('[OK] '+c.substring(0,80));
}catch(e){
log('[ERR] '+c.substring(0,80)+' | '+(e.message||''));
}
}
log('Reset Props complete');
})());
}

if(modalCats.duck){
jobs.push((async()=>{
log('Category: Duck Props');
for(const p of duckList){
const ex=await exists(p.prop);
if(!ex){
log('[SKIP] '+p.prop+' (missing)');
continue;
}
try{
await sh('su -c resetprop -n --delete '+p.prop);
log('[DEL] '+p.prop);
}catch(e){
log('[ERR] '+p.prop+' | '+(e.message||''));
}
}
log('Duck Props complete');
})());
}

if(modalCats.pif){
jobs.push((async()=>{
log('Category: PIF Props');
for(const p of deleteProps){
if(!pifList.includes(p.prop))continue;
const ex=await exists(p.prop);
if(!ex){
log('[SKIP] '+p.prop+' (missing)');
continue;
}
try{
await sh('su -c resetprop -n --delete '+p.prop);
log('[DEL] '+p.prop);
}catch(e){
log('[ERR] '+p.prop+' | '+(e.message||''));
}
}
log('PIF Props complete');
})());
}

if(modalCats.detection){
jobs.push((async()=>{
log('Category: Detection Props');
for(const p of detectedProps){
try{
await sh('su -c resetprop -n --delete '+p.prop);
log('[DEL] '+p.prop);
}catch(e){
log('[ERR] '+p.prop+' | '+(e.message||''));
}
}
log('Detection Props complete');
})());
}

if(modalCats.romhide){
jobs.push((async()=>{
log('Category: ROM Hide');
try{
const script="getprop | sed 's/^\\[//; s/\\]:.*//' | grep -i -E '("+romKeywords+")' | while IFS= read -r prop; do [ -z \"$prop\" ] && continue; echo \"FOUND: $prop\"; if su -c resetprop -n --delete \"$prop\" 2>/dev/null; then echo \"DELETED: $prop\"; else echo \"FAILED: $prop\"; fi; done; echo \"ROM Hide Finished\"";
const out=await sh(script,15000);
const lines=out.split('\n');
for(const line of lines){
if(line.trim())log(line.trim());
}
}catch(e){
log('ROM Hide error: '+(e.message||''));
}
})());
}

await Promise.all(jobs);

log('Compacting prop database...');
try{
await sh('su -c resetprop --compact >/dev/null 2>&1 || true');
log('Compacted successfully');
}catch(e){
log('Compact warning: '+(e.message||''));
}

const elapsed=((Date.now()-startTime)/1000).toFixed(1);
log('=== EXECUTION COMPLETE ('+elapsed+'s) ===');

coreLabel.textContent='CLEANED';
coreSub.textContent='All selected props fixed';
statusText.textContent='All fixed';
statusPill.className='chip chip-ok';

fixBtn.classList.remove('loading');
fixLabel.textContent='Done';
toast('All props applied and compacted','ok');

setTimeout(async()=>{
coreLabel.textContent='SCANNING DEVICE';
coreSub.textContent='Analyzing system properties...';
fixBtn.disabled=false;
fixLabel.textContent='Fix Detection';
statusText.textContent='Scanning device';
statusPill.className='chip chip-muted';
await autoScan();
},3500);
}

hasKsu=!!getApi();
if(!hasKsu){
toast('KSU API unavailable','err');
showErrorState('KSU API not available');
log('KSU API not available on startup');
}else{
autoScan();
}
