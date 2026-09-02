function popup(msg) {
  try {
    if (typeof window.toast === "function") { window.toast(String(msg)); return; }
    if (window.kernelsu && typeof window.kernelsu.toast === "function") { window.kernelsu.toast(String(msg)); return; }
    if (typeof ksu === "object" && typeof ksu.toast === "function") { ksu.toast(String(msg)); return; }
  } catch {}

  let t = document.querySelector(".toast");
  if (!t) {
    t = document.createElement("div");
    t.className = "toast";
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove("show"), 2500);
}

function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).then(() => popup("Copied to clipboard"));
  } else {
    const ta = document.createElement("textarea");
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    ta.remove();
    popup("Copied to clipboard");
  }
}

function openExternal(url) {
  if (typeof ksu !== "undefined" && ksu.exec) {
    ksu.exec(`nohup am start -a android.intent.action.VIEW -d "${url}" > /dev/null 2>&1 &`);
    popup("Opening link...");
  } else if (typeof sh !== "undefined") {
    sh(`nohup am start -a android.intent.action.VIEW -d "${url}" > /dev/null 2>&1 &`);
    popup("Opening link...");
  } else {
    window.open(url, "_blank");
    popup("Opening link...");
  }
}

const featuredData = [
  {
    label: "Binance Pay",
    sub: "Fast & Easy",
    address: "69695263",
    qr: "https://raw.githubusercontent.com/MeowDump/Integrity-Box/old/DUMP/binance.png"
  }
];

const gridData = [
  {
    label: "TRC20 USDT",
    sub: "Tron Network",
    address: "TCfhyVTfJDw8gHQT8Ph7DknNgie6ZAH5Bt"
  },
  {
    label: "BEP20 USDT",
    sub: "BNB Chain",
    address: "0x6b3f76339f2953db765dd2fb305784643e7d49df"
  },
  {
    label: "BNB Smart Chain",
    sub: "Native BNB",
    address: "0x33a6b33b40d54e83d88ca6f2f1ae8532248316eb"
  },
  {
    label: "Bitcoin",
    sub: "BTC Network",
    address: "bc1pt4hc00jkgf75f7hhwkume4utwux2jqwc0343zsnxafvqp6zfmtqqu4htfu"
  },
  {
    label: "Ethereum",
    sub: "ERC20 / ETH",
    address: "0x33a6b33b40d54e83d88ca6f2f1ae8532248316eb"
  },
  {
    label: "Solana",
    sub: "SOL Network",
    address: "CJhhei8bAWt4HinNofqxydVCXcGX1afDNKN9hwi1LoGR"
  },
  {
    label: "TON",
    sub: "The Open Network",
    address: "UQD1ppd0dcSK73HPd9uPYAXLxmtRuNY9tzzUt8t4_Z9K0kKb"
  },
  {
    label: "LiteCoin",
    sub: "LTC Network",
    address: "ltc1q4nywcj2l06rkat0nzccr9xj8hq9zsvhlwau80h"
  }
];

function payCardHtml(d, featured) {
  const qr = featured ? `<img src="${d.qr}" class="qr" alt="${d.label} QR">` : "";
  return `
    <div class="pay-card${featured ? " featured" : ""}">
      <div>
        <div class="pay-title">${d.label}</div>
        <div class="pay-sub">${d.sub}</div>
      </div>
      ${qr}
      <div class="addr-bar">
        <span class="addr-text mono">${d.address}</span>
        <button class="copy-btn" data="${d.address}">Copy</button>
      </div>
    </div>
  `;
}

function renderPayments() {
  const featured = document.getElementById("paymentFeatured");
  const grid = document.getElementById("paymentGrid");
  featured.innerHTML = featuredData.map(d => payCardHtml(d, true)).join("");
  grid.innerHTML = gridData.map(d => payCardHtml(d, false)).join("");
}

function getPlatformIcon(link) {
  if (!link) return "";
  if (link.includes("github.com")) {
    return `<svg class="platform-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>`;
  }
  if (link.includes("t.me") || link.includes("telegram")) {
    return `<svg class="platform-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.479.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>`;
  }
  return "";
}

function renderContributors(contributors) {
  const container = document.getElementById("contributorsList");
  container.innerHTML = "";

  contributors.forEach(c => {
    const hasData = c.name && c.name.trim().length > 0;
    const el = document.createElement("div");
    el.className = hasData ? "contributor-card" : "contributor-card empty";
    if (!hasData) el.classList.add("empty");

    if (hasData && c.link) {
      el.addEventListener("click", () => openExternal(c.link));
    }

    const platformIcon = hasData ? getPlatformIcon(c.link) : "";

    const avatarHtml = hasData && c.avatar
      ? `<img src="${c.avatar}" class="contributor-avatar" alt="${c.name}" onerror="this.style.display='none';this.parentElement.querySelector('.avatar-placeholder').style.display='flex'">`
      : "";

    const placeholderHtml = (!hasData || !c.avatar)
      ? `<div class="avatar-placeholder"${hasData && c.avatar ? ` style="display:none"` : ""}>${hasData ? c.name.charAt(0).toUpperCase() : "?"}</div>`
      : "";

    const langsHtml = hasData && c.languages && c.languages.length > 0
      ? `<div class="contributor-langs">${c.languages.map(l => `<span class="lang-tag">${l}</span>`).join("")}</div>`
      : "";

    const nameText = hasData ? c.name : "Available";
    const roleText = hasData ? c.role : "Slot";

    el.innerHTML = `
      ${platformIcon}
      ${avatarHtml}
      ${placeholderHtml}
      <div class="contributor-name">${nameText}</div>
      <div class="contributor-role">${roleText}</div>
      ${langsHtml}
    `;

    container.appendChild(el);
  });
}

document.addEventListener("click", e => {
  const btn = e.target.closest(".copy-btn");
  if (!btn) return;

  copyText(btn.getAttribute("data"));

  btn.textContent = "Done";
  btn.classList.add("done");

  setTimeout(() => {
    btn.textContent = "Copy";
    btn.classList.remove("done");
  }, 1500);
});

renderPayments();

fetch("../TRANSLATIONS/contributors.json")
  .then(r => r.json())
  .then(data => renderContributors(data))
  .catch(() => {
    document.getElementById("contributorsList").innerHTML =
      `<div class="muted small" style="grid-column:1/-1;text-align:center;padding:16px">Unable to load contributors</div>`;
  });
