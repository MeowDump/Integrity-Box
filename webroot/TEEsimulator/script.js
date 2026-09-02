function popup(msg,type="info"){
  try{
    if(typeof window.toast==="function"){window.toast(String(msg));return;}
    if(window.kernelsu && typeof window.kernelsu.toast==="function"){window.kernelsu.toast(String(msg));return;}
    if(typeof ksu==="object" && typeof ksu.toast==="function"){ksu.toast(String(msg));return;}
  }catch{}
  let t=document.querySelector(".toast");
  if(!t){
    t=document.createElement("div");
    t.className="toast";
    document.body.appendChild(t);
  }
  t.textContent=msg;
  t.classList.add("show");
  clearTimeout(t._timer);
  t._timer=setTimeout(()=>t.classList.remove("show"),2500);
}

async function runShell(cmd){
  return new Promise((res, rej) => {
    const execTarget =
      window.parent?.ksu?.exec ? window.parent.ksu :
      window.ksu?.exec        ? window.ksu :
      null;

    if (!execTarget || typeof execTarget.exec !== "function") {
      rej("ksu.exec not available");
      return;
    }

    const cb = "cb_" + Date.now() + "_" + (Math.random()*9999|0);

    (window.parent || window)[cb] = (c, o, e) => {
      delete (window.parent || window)[cb];
      if (c === 0) res((o || "").replace(/\r/g, ""));
      else rej(e || o || "error");
    };

    execTarget.exec(cmd, "{}", cb);
  });
}

function esc(s){
  return "'"+s.replace(/'/g,"'\\''")+"'"
}

const TARGET="/data/adb/tricky_store/target.txt";
const TARGET_BAK="/sdcard/tee_simulator_target.txt.bak";
const KEY_KEYBOX2="keybox2.xml";
const KEY_PRIVATE="keybox3.xml";
const BLACKLIST_FILE = "/data/adb/Box-Brain/blacklist.txt";

const appsBody=document.getElementById("appsBody");
const btnLoadMore=document.getElementById("btnLoadMore");
const pkgHeader=document.getElementById("pkgHeader");
const filterEl=document.getElementById("filter");
const selCountEl=document.getElementById("selCount");

let installedApps=[];
let visibleApps=[];
let targetMap={"__GLOBAL__":[]};
let selectedSet=new Set();
let renderIndex=0;
const PAGE=80;

async function readLines(p){
  try{
    const out=await runShell(`if [ -f ${esc(p)} ]; then cat ${esc(p)}; fi`);
    return out.split("\n").map(x=>x.trim()).filter(Boolean);
  }catch{return [];}
}

async function readBlacklist(){
  try{
    const lines = await readLines(BLACKLIST_FILE);
    return new Set(
      lines
        .map(l => l.trim())
        .filter(l => l && !l.startsWith("#"))
    );
  }catch{
    return new Set();
  }
}

async function writeLines(p,lines){
  try{
    const q=lines.map(l=>esc(l)).join(" ");
    await runShell(`mkdir -p $(dirname ${esc(p)}) && printf "%s\\n" ${q} > ${esc(p)}`);
    return true;
  }catch{return false;}
}

function parsePm(out){
  return out.split("\n")
    .map(l=>l.trim())
    .filter(Boolean)
    .map(l=>({pkg:l.replace("package:","")}));
}

const EXTRA_SYSTEM_APPS = [
  "com.android.vending",
  "com.google.android.gms"
];

async function fetchApps(){
  try{
    const userOut = await runShell("pm list packages -3 || true");
    const userApps = parsePm(userOut);

    const systemApps = [];
    for (const pkg of EXTRA_SYSTEM_APPS) {
      try {
        await runShell(`pm path ${pkg}`);
        systemApps.push({ pkg });
      } catch {
      }
    }

    const map = new Map();
    [...systemApps, ...userApps].forEach(a => map.set(a.pkg, a));

    return [...map.values()];
  } catch {
    return [];
  }
}

function parseTarget(lines){
  const map={"__GLOBAL__":[]};
  let cur="__GLOBAL__";
  for(const l of lines){
    if(l.startsWith("[") && l.endsWith("]")){
      cur=l.slice(1,-1);
      map[cur]=map[cur]||[];
      continue;
    }
    map[cur].push(l);
  }
  return map;
}

function base(r){
  return r.replace(/[!?]$/,"");
}

function detectMode(r){
  if(r.endsWith("!")) return "generate";
  if(r.endsWith("?")) return "leaf";
  return "auto";
}

function findMapping(pkg){
  for(const sec in targetMap){
    for(const raw of targetMap[sec]){
      if(base(raw)===pkg)
        return{sec,raw};
    }
  }
  return null;
}

function createRow(app){
  const div=document.createElement("div");
  div.className="app-row";
  div.dataset.pkg=app.pkg;

  div.innerHTML=`
    <img class="app-icon" data-src="ksu://icon/${app.pkg}" alt="" onerror="this.remove()">
    <div class="segment" data-pkg="${app.pkg}">
      <button data-k="default">Default</button>
      <button data-k="keybox2">Personal</button>
      <button data-k="private">Private</button>
    </div>
    <select class="modeSel" data-pkg="${app.pkg}" style="width:auto;min-height:32px">
      <option value="auto">AUTO</option>
      <option value="generate">GENERATE</option>
      <option value="leaf">LEAF</option>
    </select>
    <span class="app-row-name pkg-default" data-pkg="${app.pkg}">${app.pkg}</span>
  `;

  div.querySelector(".app-row-name").onclick = () => toggleSelect(app.pkg);

  return div;
}

function toggleSelect(pkg){
  if(selectedSet.has(pkg)) selectedSet.delete(pkg);
  else selectedSet.add(pkg);
  applySelectionStyles();
}

function applySelectionStyles(){
  document.querySelectorAll("#appsBody .app-row").forEach(row=>{
    const pkg=row.dataset.pkg;
    row.classList.toggle("selected-row", selectedSet.has(pkg));
  });
  selCountEl.textContent=selectedSet.size+" selected";
}

pkgHeader.onclick = () => {
  if(selectedSet.size !== visibleApps.length){
    visibleApps.forEach(a => selectedSet.add(a.pkg));
  } else {
    selectedSet.clear();
  }
  applySelectionStyles();
};

function clearTable(){
  appsBody.innerHTML="";
  renderIndex=0;
}

function renderApps(list){
  visibleApps=list;
  clearTable();
  appendChunk();
  setupIconLazyLoading();
}

function appendChunk(){
  const frag=document.createDocumentFragment();
  const end=Math.min(renderIndex+PAGE, visibleApps.length);

  for(let i=renderIndex;i<end;i++){
    frag.appendChild(createRow(visibleApps[i]));
  }

  appsBody.appendChild(frag);
  renderIndex=end;
  btnLoadMore.style.display = renderIndex < visibleApps.length ? "block" : "none";
  refreshRowBindings();
  applySelectionStyles();
}

btnLoadMore.onclick = appendChunk;

function applyPkgColor(pkg){
  const pkgCell = document.querySelector(`.app-row-name[data-pkg="${pkg}"]`);
  if(!pkgCell) return;

  const map=findMapping(pkg);
  if(!map){
    pkgCell.className="app-row-name pkg-default";
    return;
  }

  if(map.sec===KEY_KEYBOX2){
    pkgCell.className="app-row-name pkg-keybox2";
  } else if(map.sec===KEY_PRIVATE){
    pkgCell.className="app-row-name pkg-private";
  } else {
    pkgCell.className="app-row-name pkg-default";
  }
}

function removePkgEverywhere(pkg){
  for(const s in targetMap){
    targetMap[s] = targetMap[s].filter(r => base(r)!==pkg);
  }
}

function refreshRowBindings(){

  document.querySelectorAll(".segment").forEach(seg=>{
    const pkg=seg.dataset.pkg;
    const btns=seg.querySelectorAll("button");

    const map=findMapping(pkg);
    if(map){
      const secName =
        map.sec==="__GLOBAL__" ? "default" :
        map.sec===KEY_KEYBOX2    ? "keybox2" :
        "private";

      btns.forEach(b => b.classList.toggle("active", b.dataset.k===secName));
      const modeSel=document.querySelector(`.modeSel[data-pkg="${pkg}"]`);
      modeSel.value=detectMode(map.raw);
    }

    btns.forEach(b=>{
      b.onclick = () => {
        const key=b.dataset.k;

        btns.forEach(x=>x.classList.remove("active"));
        b.classList.add("active");

        removePkgEverywhere(pkg);

        const sec =
          key==="default" ? "__GLOBAL__" :
          key==="keybox2"    ? KEY_KEYBOX2 :
                              KEY_PRIVATE;

        const modeSel=document.querySelector(`.modeSel[data-pkg="${pkg}"]`);
        const mode=modeSel.value;
        const raw =
          mode==="generate"? pkg+"!" :
          mode==="leaf"?     pkg+"?" :
                            pkg;

        targetMap[sec] = targetMap[sec]||[];
        targetMap[sec].push(raw);

        applyPkgColor(pkg);

        popup(`Mapped ${pkg} → ${b.dataset.k.toUpperCase()}`);
      };
    });

    const modeSel=document.querySelector(`.modeSel[data-pkg="${pkg}"]`);
    modeSel.onchange = () => {
      const activeBtn = seg.querySelector("button.active");
      if(!activeBtn) return;

      const sec =
        activeBtn.dataset.k==="default" ? "__GLOBAL__" :
        activeBtn.dataset.k==="keybox2"    ? KEY_KEYBOX2 :
                                            KEY_PRIVATE;

      removePkgEverywhere(pkg);

      const mode=modeSel.value;
      const raw =
        mode==="generate"? pkg+"!" :
        mode==="leaf"?     pkg+"?" :
                          pkg;

      targetMap[sec] = targetMap[sec]||[];
      targetMap[sec].push(raw);

      applyPkgColor(pkg);
    };
  });
}

document.getElementById("btnAddSelected").onclick = async () => {
  const sel = [...selectedSet];
  if(sel.length===0) return;

  const kb=document.getElementById("bulkKeybox").value;
  const mode=document.getElementById("bulkMode").value;

  const sec =
    kb==="default" ? "__GLOBAL__" :
    kb==="keybox2"    ? KEY_KEYBOX2 :
                      KEY_PRIVATE;

  for(const pkg of sel){
    removePkgEverywhere(pkg);
  }

  targetMap[sec] = targetMap[sec] || [];

  sel.forEach(pkg=>{
    const raw =
      mode==="generate"? pkg+"!" :
      mode==="leaf"?     pkg+"?" :
                       pkg;
    targetMap[sec].push(raw);
    applyPkgColor(pkg);
  });

  await persist();
  await refresh();
};

document.getElementById("btnRemoveSelected").onclick = async () => {
  const sel=[...selectedSet];
  sel.forEach(pkg=>removePkgEverywhere(pkg));
  await persist();
  await refresh();
};

function setupIconLazyLoading(){
  const imgs = document.querySelectorAll("img.app-icon[data-src]");

  if (!("IntersectionObserver" in window)) {
    imgs.forEach(img => img.src = img.dataset.src);
    return;
  }

  const obs = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      const img = e.target;
      img.src = img.dataset.src;
      img.onload = () => {};
      img.onerror = () => {
        img.remove();
      };
      obs.unobserve(img);
    });
  }, { rootMargin: "100px" });

  imgs.forEach(img => obs.observe(img));
}

async function persist(){
  const out=[];

  if(targetMap["__GLOBAL__"]?.length){
    targetMap["__GLOBAL__"].forEach(x=>out.push(x));
    out.push("");
  }

  if(targetMap[KEY_KEYBOX2]?.length){
    out.push(`[${KEY_KEYBOX2}]`, ...targetMap[KEY_KEYBOX2], "");
  }
  if(targetMap[KEY_PRIVATE]?.length){
    out.push(`[${KEY_PRIVATE}]`, ...targetMap[KEY_PRIVATE], "");
  }

  while(out.length && out[out.length-1]==="") out.pop();

  await writeLines(TARGET, out);
}

document.getElementById("btnSave").onclick = async () => {
  await persist();
  popup("Saved.");
};

document.getElementById("btnBackup").onclick = async () => {
  try {
    await runShell(`cp ${esc(TARGET)} ${esc(TARGET_BAK)} 2>/dev/null || true`);
    popup("Backup created successfully!");
  } catch(e){
    popup("Backup failed: " + e);
  }
};

document.getElementById("btnRestore").onclick = async () => {
  try {
    await runShell(`cp ${esc(TARGET_BAK)} ${esc(TARGET)} 2>/dev/null || true`);
    await refresh();
    popup("Restored from backup.");
  } catch(e){
    popup("Restore failed: " + e);
  }
};

let debounceTimer;
filterEl.oninput = () => {
  clearTimeout(debounceTimer);
  debounceTimer=setTimeout(()=>{
    const q = filterEl.value.toLowerCase();
    const list = installedApps.filter(a=>a.pkg.toLowerCase().includes(q));
    renderApps(list);
  }, 300);
};

async function refresh(){
  selectedSet.clear();
  selCountEl.textContent="0 selected";
  appsBody.innerHTML = `<div class="muted">Loading…</div>`;

  installedApps = await fetchApps();

  const blacklist = await readBlacklist();
  installedApps = installedApps.filter(a => !blacklist.has(a.pkg));

  const lines = await readLines(TARGET);
  targetMap = parseTarget(lines);

  renderApps(installedApps);

  installedApps.forEach(a=>applyPkgColor(a.pkg));
}

(async()=>{
  await refresh();
})();
