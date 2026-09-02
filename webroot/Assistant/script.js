const faq = {
  "General": [
    { q:"What are the requirements?", a:"Well, it depends on your ROM, Zygisk isn't needed if you're using Google pixel stock ROM. Anyways here are the recommended modules which works universally on all devices. <p> 1. Tricky Store <p/> <p> 2. Integrity Box <p/> <p> 3. Zygisk Next <p/> <p> You can download them by opening integrity box's webui  <p/> <p> <p/> <p> Module Settings > Integrity downloader<p> . <p/> Go back to modules tab & click on integrity box's action button. Modules will be downloaded into /sdcard/Downloads/IntegrityModules folder<p/>" },
    { q:"Why does my device pass Play Integrity but still fail ‘Device certification / license’ within apps?", a:"Passing Play Integrity doesn’t always mean device is certified. <p> Google Play certification/licensing checks may also require valid GMS certification, correct vendor‑partition signatures, valid attestation keys, and genuine vendor keybox. <p> If those are tampered with (by custom ROM, modded firmware, or spoof), apps checking “certified device status” might still fail even if integrity test passes." },
    { q:"Fix Device not Certified", a:"You need to pass atleast DEVICE INTEGRITY then Open WebUI, Go to FIX DEVICE IS NOT CERTIFIED button, keep in mind that your root & zygisk should be hidden properly, otherwise it won't work." },
    { q:"I don't know how to use WebUI", a:"I got you bro, If you're using magisk, then you've to Install KSU WebUI app & grant it root permission to use WebUI features of you're installed modules. <p> If you want to know about the usage of a specific setting, check Integrity Box's github repository, everything is well explained there. <p\>" },
    { q:"Fingerprint not working", a:"Open WebUI, Go to MODULE SETTING, and enable KILL SWITCH toggle & reboot your device" },
    { q:"Magisk Tips?", a:"If you're using magisk, make sure to disable magisk's built-in Zygisk & add your banking apps into denylist. GMS & Play Services process will be added automatically via Integrity Box. Also hide your magisk app by changing it's name from magisk settings.." }
  ],
  "Integrity": [
    { q:"Why is Strong Play Integrity failing?", a:"Make sure you have installed the recommended modules. Keep in mind that not all ROMs can pass Play Integrity, no matter you've disabled ROM's inbuilt GMS spoofing or updated keybox/fingerprint. You can also try downgrading your playstore version to v40.0.13-23 <p> Play Integrity fails when bootloader is unlocked (not spoofed) or hardware keybox isn't valid. Check for conflicting modules as well. Sometimes using too many modules/lsposed apps exposes root environment. <p/>" },
    { q:"Why do some banking apps still not working even if Play Integrity shows Strong?", a:"Because many banking apps implement their own root/environment detection, beyond Play Integrity. <p> They can check system props (like ro.debuggable), existence of root binaries, SELinux status, unusual filesystem traces, custom kernel or recovery markers, debug build‑flags, and flagged apps etc. <p> Even if Integrity‑Box fixes majority of stuff mentioned above, you still need root‑hiding tools such as HideMyApplist, Denylist etc clean storage (no TWRP folder, no root files visible), and sometimes a clean ROM (stock or near‑stock) for best results." },
    { q:"I passed Play Integrity but some apps like Google Pay / Wallet / UPI still don’t work, why?", a:"That’s because passing Play Integrity is only one side. <p> Many “payment/wallet” apps check extra signals like bootloader lock status, vendor keybox validity, hardware‑backed attestation, or app‑specific additional checks. <p> Also, if your ROM has patched or spoofed GMS (Google Mobile Services) and uses custom keybox/keystore, it may conflict with modules trying to spoof, modules like Tricky Store,sometimes conflict with ROM‑level spoofing." },
    { q:"My device is running a custom ROM, will IntegrityBox work reliably?", a:"Yes, but keep in mind that Custom ROMs make things harder. <p> Many custom ROMs come with their own modifications to system props, keybox, GMS spoofing or security patch metadata. These changes often interfere with spoofing modules. <p> For custom ROMs: first disable or clean any pre‑built spoofing or keybox tricks, restore stock props if possible, then apply Integrity‑Box + trickystore. Only then try passing Device/Strong integrity." },
    { q:"Which modules should I combine with Integrity‑Box to maximize banking‑app compatibility?", a:"A commonly recommended setup is: <p> • Integrity‑Box (for props/keybox spoofing)  <p> • Clean zygote injection layer (e.g. Zygisk Next)  <p> • DenyList / Hide‑Magisk‑Manager (so root‑manager app isn’t visible) or use spoofed version of KSU manager  <p> • Clear Play Store + Google Services data after flashing/patching  <p> • Reboot and test using Play Integrity checker/app  <p> This combo is often suggested for rooted phones on custom ROMs to pass checks and run banking/UPI apps." },
    { q:"My banking app still shows ‘root detected’ after passing all integrity checks, what extra measures can help?", a:"Here are extra measures often recommended: <p> • Remove/rename root‑manager apps (Magisk Manager etc.), or keep them hidden.  <p> • Remove residual traces: TWRP folder, recovery backups, root‑app leftovers in storage.  <p> • Use DenyList or Hide‑Magisk + include banking apps.  <p> • For custom ROMs: avoid prebuilt ROM‑level spoofing that conflicts with your modules.  <p> • Use MEOW 2.0 HMA config" },
    { q:"Does updating Google Play Services or Play Store break spoofing modules?", a:"Often yes. Google Play Services updates may re‑validate keys, vendor certificates or integrity metadata, which may invalidate spoofing or keybox tricks. <p> After such updates, you may need to reapply spoofing or re‑flash/ modules to retain spoofed integrity. Many forum users report requiring re‑spoof after major Play Services updates." },
    { q:"How to clean old root traces fully before applying IntegrityBox and spoofing?", a:"Suggested cleanup steps: <p> • Uninstall all root‑manager apps and modules.  <p> • Remove folders like /sdcard/TWRP etc.  <p> • Clear cache/data for Google Services and banking apps.  <p> • Reboot.  <p> • Then apply the recommended modules.  <p> Many users on XDA confirm this full clean + fresh install often resolves persistent root detection issues." },
    { q:"Why does my device show Basic integrity even after spoofing and proper root hiding?", a:"If your android version is A13 or above, use SUPREME profile.. if it's A12 or below, then use LEGACY profile with downgraded version (v40.xx) of playstore" },
    { q:"What if I still fail Strong Integrity even after installing IntegrityBox?", a:"Passing Strong Integrity can also depend on hardware keybox validity, bootloader status, vendor-partition patches, and conflicting modules. <p> If you’re on a custom ROM or have SELinux/permissive, or if other modules tamper with system props, IntegrityBox alone may not be enough." },
    { q:"Will using root-hiding modules along with Integrity-Box improve success for banking apps?", a:"Often yes, many users report that combining IntegrityBox with root-hiding tools helps avoid detection by banking apps. <p> However, root-hiding + spoofing is a game of cat–mouse and may not work universally." },
    { q:"Why do banking or wallet apps still detect root even though Play Integrity says 'pass'?", a:"Because Play Integrity is only one part of detection. <p> Many apps also perform root/environment detection at runtime. If root-hiding is incomplete or other modules leave traces (e.g. custom recovery folder, SELinux flags, debug props), apps may still detect tampering." }
  ],
  "Curiosity": [
    { q:"After an Android update or ROM update, I have to reapply spoofing, why?", a:"Because system updates or ROM changes often overwrite or reset key system files and security metadata. <p> Security‑patch date, vendor partition data, keybox validity and build props may be reset. <p> As a result, spoofing done by Integrity‑Box or other fixes becomes invalid, you need to re‑spoof, re‑apply settings, or re‑test after each major update to ensure compatibility." },
    { q:"Is there any guarantee that IntegrityBox will make all apps work flawlessly?", a:"No. There is no universal guarantee. <p> Modern detection systems (like updated Play Integrity, custom native checks by apps, bootloader‑unlock detection, hardware attestation) continue evolving. <p> IntegrityBox increases the chance of passing integrity checks, but due to variables (device model, ROM, kernel, other modules, app-specific checks), it's always a “best‑effort” solution." },
    { q:"How to debug if spoofing failed, where to start?", a:"Start by checking: <p> • Are device props (ro.build.*) spoofed properly?  <p> • Is keybox/keystore valid?  <p> • Is SELinux enforcing?  <p> • Any conflicting root‑hiding or system‑mod modules installed?  <p> • Has cached data (Play Store, Google Services) been cleared after modules applied & before testing apps?  <p> • Are you using latest module versions and correct config for your ROM/kernel?  <p> This systematic check helps isolate what’s breaking integrity or causing detection." },
    { q:"Is it better to use kernel‑level root (like KernelSU) instead of user‑space root (Magisk) for banking app stealth?", a:"Many users on XDA report that kernel‑level root solutions (like KernelSU) tend to be stealthier because they avoid certain userspace traces that detection detects (root binaries, Magisk dirs, etc.). <p> Coupled with IntegrityBox, KernelSU may result in fewer detections than traditional Magisk setups. But results vary by device, ROM, and kernel patches." },
    { q:"Does every device / ROM support IntegrityBox equally?", a:"No. Results may vary depending on device vendor, Android version, ROM, SELinux mode, kernel, vendor-partition changes, and how 'stock' your firmware is. <p> Custom ROMs or heavy modifications reduce the chance of a clean pass." },
    { q:"What modules should I avoid to reduce conflicts with IntegrityBox?", a:"Avoid modules that heavily modify system props, SELinux setting, kernel behavior, root-detection hooks, or GMS/Play services tampering. And those modules which modifies tricky store's target.txt<p> Such modules may conflict with integrity spoofing and cause detection failures or boot issues." },
    { q:"Is using IntegrityBox a permanent fix or will I need to reconfigure after updates (ROM / kernel)?", a:"It’s not guaranteed permanent. <p> System updates, kernel or vendor changes, ROM updates frequently break spoofing or keybox validity; you may need to reapply or re‑configure play integrity related after updates." },
    { q:"Can this break apps?", a:"No." }
  ],
};

/* KEYWORD FILTERS */
const filters = {
  "root": "Root detection info: Integrity-Box cannot fully hide root by itself.",
  "useless": "😂😂😂",
  "telegram": "Check our Updates Channel: https://t.me/MeowRedirect",
  "hi": "Hi bro, please select your query so that I can assist you",
  "hello": "Hi bro, please select your query so that I can assist you",
  "thank": "Welcome dude, Happy to help you 😊",
  "pif": "Starting from v28, PIF is not needed when using integrity box",
  "bug": "You can report bugs here: https://t.me/TempMeow"
};

let currentCategory = "General";

/* BUILD TABS */
const tabContainer = document.getElementById("tabs");
Object.keys(faq).forEach(cat => {
  const t = document.createElement("div");
  t.className = "tab" + (cat === currentCategory ? " active" : "");
  t.textContent = cat;
  t.onclick = () => { currentCategory = cat; buildTabs(); buildQuestions(); };
  tabContainer.appendChild(t);
});
function buildTabs() {
  document.querySelectorAll(".tab").forEach(t => {
    t.classList.toggle("active", t.textContent === currentCategory);
  });
}

/* BUILD QUESTIONS */
const faqPanel = document.getElementById("faqPanel");
function buildQuestions(filter = "") {
  const container = document.getElementById("questions");
  container.innerHTML = "";
  faq[currentCategory].forEach(item => {
    if (filter && !item.q.toLowerCase().includes(filter.toLowerCase())) return;
    const el = document.createElement("div");
    el.className = "q-btn";
    el.textContent = item.q;
    el.onclick = () => {
      ask(item.q, item.a);
      minimizeFAQ();
    };
    container.appendChild(el);
  });
}
buildQuestions();

/* SEARCH */
document.getElementById("search").addEventListener("input", e => {
  const val = e.target.value.trim();
  buildQuestions(val);
});

/* CHAT */
const chat = document.getElementById("chat");

function ask(q, a) {
  appendBubble(q, "user-msg");
  scrollChat();
  showTyping(() => appendBubble(a, "bot-msg"));
}

function sendMessage() {
  const input = document.getElementById("userInput");
  const text = input.value.trim();
  if (!text) return;

  input.value = "";
  appendBubble(text, "user-msg");
  scrollChat();

  // keyword filters
  for (const key in filters) {
    if (text.toLowerCase().includes(key)) {
      showTyping(() => appendBubble(filters[key], "bot-msg"));
      return;
    }
  }

  const inputWords = text
    .toLowerCase()
    .split(/\s+/)
    .filter(w => w.length > 3);

  if (!inputWords.length) {
    showTyping(() =>
      appendBubble(
        "Please type a little more detail so I can help 🙂",
        "bot-msg"
      )
    );
    return;
  }

  let bestMatch = null;
  let bestScore = 0;

  for (const cat in faq) {
    for (const item of faq[cat]) {
      const qWords = item.q.toLowerCase().split(/\s+/);

      let score = 0;
      inputWords.forEach(w => {
        if (qWords.some(qw => qw.includes(w) || w.includes(qw))) {
          score++;
        }
      });

      if (score > bestScore) {
        bestScore = score;
        bestMatch = item;
      }
    }
  }

  if (bestMatch && bestScore >= 2) {
    showTyping(() => appendBubble(bestMatch.a, "bot-msg"));
    return;
  }

  // suggestions
  let suggestions = [];

  for (const cat in faq) {
    for (const item of faq[cat]) {
      const qWords = item.q.toLowerCase().split(/\s+/);
      if (
        inputWords.some(w =>
          qWords.some(qw => qw.includes(w) || w.includes(qw))
        )
      ) {
        suggestions.push(item.q);
      }
    }
  }

  if (suggestions.length) {
    showTyping(() =>
      appendBubble(
        "Did you mean:\n- " +
          [...new Set(suggestions)].slice(0, 3).join("\n- "),
        "bot-msg"
      )
    );
  } else {
    showTyping(() =>
      appendBubble(
        "I couldn't find an exact match. Please select a FAQ above or contact the developer.",
        "bot-msg"
      )
    );
  }
}

function appendBubble(text, cls) {
  const el = document.createElement("div");
  el.className = cls;

  if (Array.isArray(text)) {
    text.forEach(p => {
      const pEl = document.createElement("p");
      pEl.textContent = p;
      el.appendChild(pEl);
    });
  } else {
    el.innerHTML = text.replace(/\n/g, "<br>");
  }

  chat.appendChild(el);
  scrollChat();
}

function showTyping(callback) {
  const t = document.createElement("div");
  t.className = "typing";
  t.textContent = "…";
  chat.appendChild(t);
  scrollChat();
  setTimeout(() => { t.remove(); callback(); scrollChat(); }, 900);
}

function scrollChat() { chat.scrollTop = chat.scrollHeight; }

/* TOGGLE FAQ PANEL */
const toggleBtn = document.getElementById("toggleBtn");
toggleBtn.onclick = () => {
  faqPanel.classList.toggle("minimized");
  toggleBtn.textContent = faqPanel.classList.contains("minimized") ? "Show Frequently Asked Questions" : "Minimize Questions";
}
function minimizeFAQ() {
  faqPanel.classList.add("minimized");
  toggleBtn.textContent = "Show Frequently Asked Questions";
}

/* LINK OPEN */
function openLink(url) {
  try { ksu.exec(`am start -a android.intent.action.VIEW -d ${url}`); alert("Opening…"); }
  catch (e) { alert("Unable to open link."); }
}
