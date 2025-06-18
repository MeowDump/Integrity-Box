const MODDIR = "/data/adb/modules/integrity_box";
const PROP = `${MODDIR}/module.prop`;

const modalBackdrop = document.getElementById("modal-backdrop");
const modalTitle = document.getElementById("modal-title");
const modalOutput = document.getElementById("modal-output");
const modalClose = document.getElementById("modal-close");

function runShell(command) {
  if (typeof ksu !== "object" || typeof ksu.exec !== "function") {
    return Promise.reject("KernelSU JavaScript API not available.");
  }
  const cb = `cb_${Date.now()}`;
  return new Promise((resolve, reject) => {
    window[cb] = (code, stdout, stderr) => {
      delete window[cb];
      code === 0 ? resolve(stdout) : reject(new Error(stderr || "Shell command failed"));
    };
    ksu.exec(command, "{}", cb);
  });
}

function popup(msg) {
  return runShell(`am start -a android.intent.action.MAIN -e mona "${msg}" -n meow.helper/.MainActivity`);
}

function openModal(title, content) {
  modalTitle.textContent = title;
  modalOutput.textContent = content || "Loading...";
  modalBackdrop.classList.remove("hidden");
}

function closeModal() {
  modalBackdrop.classList.add("hidden");
}

async function getModuleName() {
  try {
    const name = await runShell(`grep '^name=' ${PROP} | cut -d= -f2`);
    document.getElementById("module-name").textContent = name.trim();
    document.title = name.trim();
  } catch {
    document.getElementById("module-name").textContent = "integrity_box";
  }
}

async function updateDashboard() {
  const statusWhitelist = document.getElementById("status-whitelist");
  const statusGms = document.getElementById("status-gms");
  const statusSusfs = document.getElementById("status-susfs");

  try {
    await runShell("[ -f /data/adb/shamiko/whitelist ]");
    statusWhitelist.textContent = "Enabled";
    statusWhitelist.className = "status-indicator enabled";
  } catch {
    statusWhitelist.textContent = "Disabled";
    statusWhitelist.className = "status-indicator disabled";
  }

  try {
    const gmsProp = await runShell("getprop persist.sys.pihooks.disable.gms_props");
    if (gmsProp.trim() === "true") {
      statusGms.textContent = "Disabled";
      statusGms.className = "status-indicator enabled";
    } else {
      statusGms.textContent = "Enabled";
      statusGms.className = "status-indicator disabled";
    }
  } catch {
    statusGms.textContent = "Unknown";
    statusGms.className = "status-indicator";
  }

  try {
    await runShell("[ -d /data/adb/modules/susfs4ksu ]");
    statusSusfs.textContent = "Detected";
    statusSusfs.className = "status-indicator enabled";
  } catch {
    statusSusfs.textContent = "Not Found";
    statusSusfs.className = "status-indicator disabled";
  }
}

document.addEventListener("DOMContentLoaded", () => {
  getModuleName();
  updateDashboard();

  document.querySelectorAll(".btn").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const script = btn.dataset.script;
      const type = btn.dataset.type;
      const command = `sh ${MODDIR}/${script}`;
      btn.classList.add("loading");
      try {
        if (type === "scanner") {
          const title = btn.innerText.trim();
          openModal(title, "Running scan...");
          const output = await runShell(command);
          modalOutput.textContent = output || "Script executed with no output.";
        } else {
          await runShell(command);
        }
      } catch (error) {
        if (type === "scanner") {
          modalOutput.textContent = `Error executing script:\n\n${error.message}`;
        } else {
          popup(`Error: ${error.message}`);
        }
      } finally {
        btn.classList.remove("loading");
        setTimeout(updateDashboard, 1000);
      }
    });
  });

  modalClose.addEventListener("click", closeModal);
  modalBackdrop.addEventListener("click", (e) => {
    if (e.target === modalBackdrop) closeModal();
  });
  
  const langDropdown = document.getElementById("lang-dropdown");
  if (langDropdown) {
    const translations = {
      en: ["Disable Auto-Whitelist Mode", "Enable Auto-Whitelist Mode", "Target All Apps", "Target User Apps", "Set Valid Keybox", "Set AOSP Keybox", "Set Custom Fingerprint", "Kill GMS Process", "Spoof PIF SDK", "Spoof Tricky Patch", "Update SusFS Config", "Banned Keybox List", "Disable GMS Spoofing", "Enable GMS Spoofing", "FIX Device not Certified", "Abnormal Detection", "Flagged Apps", "Props Detection", "Module Info", "Report a Problem", "Help Group", "Update Channel"],
      id: ["Nonaktifkan Mode Daftar Putih Otomatis", "Aktifkan Mode Daftar Putih Otomatis", "Targetkan Semua Aplikasi", "Targetkan Aplikasi Pengguna", "Setel Keybox yang Valid", "Setel Keybox AOSP", "Setel Sidik Jari Kustom", "Matikan Proses GMS", "Spoof PIF SDK", "Spoof Patch Tricky", "Perbarui Konfigurasi SusFS", "Daftar Keybox yang Diblokir", "Nonaktifkan Spoofing GMS", "Aktifkan Spoofing GMS", "PERBAIKI Perangkat Tidak Bersertifikat", "Deteksi Abnormal", "Aplikasi yang Ditandai", "Deteksi Properti", "Info Modul", "Laporkan Masalah", "Grup Bantuan", "Saluran Pembaruan"],
      pl: ["Wyłącz tryb automatycznej białej listy", "Włącz tryb automatycznej białej listy", "Namierz wszystkie aplikacje", "Namierz aplikacje użytkownika", "Ustaw prawidłowy Keybox", "Ustaw Keybox AOSP", "Ustaw niestandardowy odcisk palca", "Zabij proces GMS", "Sfałszuj PIF SDK", "Sfałszuj łatkę Tricky", "Zaktualizuj konfigurację SusFS", "Lista zbanowanych Keyboxów", "Wyłącz spoofing GMS", "Włącz spoofing GMS", "NAPRAW urządzenie nie jest certyfikowane", "Wykrywanie nieprawidłowości", "Oznaczone aplikacje", "Wykrywanie właściwości", "Informacje o module", "Zgłoś problem", "Grupa pomocy", "Kanał aktualizacji"],
      ru: ["Отключить авто-белый список", "Включить авто-белый список", "Добавить все приложения в список", "Добавить только пользовательские приложения", "Установить действительный Keybox", "Установить AOSP Keybox", "Установить пользовательский отпечаток", "Завершить процесс GMS", "Спуфинг PIF SDK", "Спуфинг патча Tricky", "Обновить конфигурацию SusFS", "Список запрещенных Keybox", "Отключить GMS Spoofing", "Включить GMS Spoofing", "ИСПРАВИТЬ: устройство не сертифицировано", "Сканировать на аномалии", "Сканировать вредоносные приложения", "Сканировать Props", "Информация о модуле", "Сообщить о проблеме", "Присоединиться к группе поддержки", "Подписаться на канал обновлений"],
      uk: ["Вимкнути авто-білий список", "Увімкнути авто-білий список", "Додати всі програми", "Додати лише програми користувача", "Встановити дійсний Keybox", "Встановити AOSP Keybox", "Встановити власний відбиток", "Зупинити процес GMS", "Підмінити PIF SDK", "Підмінити патч Tricky", "Оновити конфігурацію SusFS", "Список заблокованих Keybox", "Вимкнути GMS Spoofing", "Увімкнути GMS Spoofing", "ВИПРАВИТИ: Пристрій не сертифіковано", "Сканувати на аномалії", "Сканувати шкідливі програми", "Сканувати Props", "Інформація про модуль", "Повідомити про проблему", "Група допомоги", "Канал оновлень"],
      hi: ["ऑटो-व्हाइटलिस्ट मोड अक्षम करें", "ऑटो-व्हाइटलिस्ट मोड सक्षम करें", "सभी ऐप्स को लक्षित करें", "उपयोगकर्ता ऐप्स को लक्षित करें", "वैध कीबॉक्स सेट करें", "AOSP कीबॉक्स सेट करें", "कस्टम फिंगरप्रिंट सेट करें", "GMS प्रक्रिया समाप्त करें", "PIF SDK को स्पूफ करें", "ट्रिकी पैच को स्पूफ करें", "SusFS कॉन्फ़िगरेशन अपडेट करें", "प्रतिबंधित कीबॉक्स सूची", "GMS स्पूफिंग अक्षम करें", "GMS स्पूफिंग सक्षम करें", "डिवाइस प्रमाणित नहीं है ठीक करें", "असामान्य पहचान", "चिह्नित ऐप्स", "प्रॉप्स पहचान", "मॉड्यूल जानकारी", "समस्या की रिपोर्ट करें", "सहायता समूह", "अपडेट चैनल"],
      te: ["ఆటో-వైట్‌లిస్ట్ మోడ్‌ను నిలిపివేయండి", "ఆటో-వైట్‌లిస్ట్ మోడ్‌ను ప్రారంభించండి", "అన్ని అనువర్తనాలను లక్ష్యం చేయండి", "వినియోగదారు అనువర్తనాలను లక్ష్యం చేయండి", "చెల్లుబాటు అయ్యే కీబాక్స్‌ను సెట్ చేయండి", "AOSP కీబాక్స్‌ను సెట్ చేయండి", "అనుకూల వేలిముద్రను సెట్ చేయండి", "GMS ప్రక్రియను ఆపండి", "PIF SDKని స్పూఫ్ చేయండి", "ట్రిక్కీ ప్యాచ్‌ను స్పూఫ్ చేయండి", "SusFS కాన్ఫిగరేషన్‌ను నవీకరించండి", "నిషేధించబడిన కీబాక్స్ జాబితా", "GMS స్పూఫింగ్‌ను నిలిపివేయండి", "GMS స్పూఫింగ్‌ను ప్రారంభించండి", "పరికరం ధృవీకరించబడలేదు సరిచేయండి", "అసాధారణ గుర్తింపు", "ఫ్లాగ్ చేయబడిన అనువర్తనాలు", "ప్రాప్స్ గుర్తింపు", "మాడ్యూల్ సమాచారం", "సమస్యను నివేదించండి", "సహాయ సమూహం", "నవీకరణ ఛానెల్"],
      ta: ["தானியங்கு வெள்ளைப்பட்டியல் பயன்முறையை முடக்கு", "தானியங்கு வெள்ளைப்பட்டியல் பயன்முறையை இயக்கு", "அனைத்து பயன்பாடுகளையும் குறிவை", "பயனர் பயன்பாடுகளை குறிவை", "சரியான கீபாக்ஸை அமை", "AOSP கீபாக்ஸை அமை", "தனிப்பயன் கைரேகையை அமை", "GMS செயல்முறையை நிறுத்து", "PIF SDK ஐ ஏமாற்று", "தந்திரமான பேட்சை ஏமாற்று", "SusFS கட்டமைப்பைப் புதுப்பி", "தடைசெய்யப்பட்ட கீபாக்ஸ் பட்டியல்", "GMS ஏமாற்றலை முடக்கு", "GMS ஏமாற்றலை இயக்கு", "சாதனம் சான்றளிக்கப்படவில்லை சரிசெய்", "இயல்பற்ற கண்டறிதல்", "கொடியிடப்பட்ட பயன்பாடுகள்", "பண்புகள் கண்டறிதல்", "தொகுதி தகவல்", "சிக்கலைப் புகாரளி", "உதவி குழு", "புதுப்பிப்பு சேனல்"],
      es: ["Desactivar modo de lista blanca automática", "Activar modo de lista blanca automática", "Apuntar a todas las aplicaciones", "Apuntar a aplicaciones de usuario", "Establecer Keybox válido", "Establecer Keybox AOSP", "Establecer huella digital personalizada", "Matar proceso de GMS", "Falsificar SDK de PIF", "Falsificar parche Tricky", "Actualizar configuración de SusFS", "Lista de Keybox prohibidos", "Desactivar suplantación de GMS", "Activar suplantación de GMS", "ARREGLAR: dispositivo no certificado", "Detección de anomalías", "Aplicaciones marcadas", "Detección de propiedades", "Información del módulo", "Informar de un problema", "Grupo de ayuda", "Canal de actualizaciones"],
      bn: ["অটো-হোয়াইটলিস্ট মোড নিষ্ক্রিয় করুন", "অটো-হোয়াইটলিস্ট মোড সক্ষম করুন", "সমস্ত অ্যাপ টার্গেট করুন", "ব্যবহারকারী অ্যাপ টার্গেট করুন", "বৈধ কী-বক্স সেট করুন", "AOSP কী-বক্স সেট করুন", "কাস্টম ফিঙ্গারপ্রিন্ট সেট করুন", "GMS প্রক্রিয়া বন্ধ করুন", "PIF SDK স্পুফ করুন", "ট্রিকি প্যাচ স্পুফ করুন", "SusFS কনফিগারেশন আপডেট করুন", "নিষিদ্ধ কী-বক্স তালিকা", "GMS স্পুফিং নিষ্ক্রিয় করুন", "GMS স্পুফিং সক্ষম করুন", "ডিভাইস প্রত্যয়িত নয় ঠিক করুন", "অস্বাভাবিক সনাক্তকরণ", "ফ্ল্যাগ করা অ্যাপ", "প্রপস সনাক্তকরণ", "মডিউল তথ্য", "সমস্যা রিপোর্ট করুন", "সহায়তা গ্রুপ", "আপডেট চ্যানেল"],
      pt: ["Desativar modo de lista de permissões automática", "Ativar modo de lista de permissões automática", "Visar todos os aplicativos", "Visar aplicativos do usuário", "Definir Keybox válido", "Definir Keybox AOSP", "Definir impressão digital personalizada", "Matar processo GMS", "Falsificar SDK PIF", "Falsificar patch Tricky", "Atualizar configuração SusFS", "Lista de Keybox banidos", "Desativar falsificação GMS", "Ativar falsificação GMS", "CORRIGIR: dispositivo não certificado", "Detecção de anomalias", "Aplicativos sinalizados", "Detecção de propriedades", "Informações do módulo", "Relatar um problema", "Grupo de ajuda", "Canal de atualização"],
      zh: ["禁用自动白名单模式", "启用自动白名单模式", "针对所有应用", "针对用户应用", "设置有效密钥盒", "设置AOSP密钥盒", "设置自定义指纹", "终止GMS进程", "伪造PIF SDK", "伪造Tricky补丁", "更新SusFS配置", "被禁密钥盒列表", "禁用GMS伪装", "启用GMS伪装", "修复设备未认证", "异常检测", "已标记应用", "属性检测", "模块信息", "报告问题", "帮助组", "更新频道"],
      fr: ["Désactiver le mode liste blanche auto", "Activer le mode liste blanche auto", "Cibler toutes les applications", "Cibler les applications utilisateur", "Définir un Keybox valide", "Définir un Keybox AOSP", "Définir une empreinte digitale personnalisée", "Tuer le processus GMS", "Falsifier le SDK PIF", "Falsifier le patch Tricky", "Mettre à jour la configuration SusFS", "Liste des Keybox bannis", "Désactiver la falsification GMS", "Activer la falsification GMS", "RÉPARER: appareil non certifié", "Détection d'anomalies", "Applications signalées", "Détection des propriétés", "Infos sur le module", "Signaler un problème", "Groupe d'aide", "Canal de mise à jour"],
      ar: ["تعطيل وضع القائمة البيضاء التلقائي", "تمكين وضع القائمة البيضاء التلقائي", "استهداف جميع التطبيقات", "استهداف تطبيقات المستخدم", "تعيين صندوق مفاتيح صالح", "تعيين صندوق مفاتيح AOSP", "تعيين بصمة مخصصة", "إنهاء عملية GMS", "تزييف PIF SDK", "تزييف باتش Tricky", "تحديث تكوين SusFS", "قائمة صناديق المفاتيح المحظورة", "تعطيل تزييف GMS", "تمكين تزييف GMS", "إصلاح الجهاز غير معتمد", "كشف غير طبيعي", "التطبيقات المبلغ عنها", "كشف الخصائص", "معلومات الوحدة", "الإبلاغ عن مشكلة", "مجموعة المساعدة", "قناة التحديثات"],
      ur: ["آٹو وائٹ لسٹ موڈ کو غیر فعال کریں", "آٹو وائٹ لسٹ موڈ کو فعال کریں", "تمام ایپس کو نشانہ بنائیں", "صارف ایپس کو نشانہ بنائیں", "درست کی باکس سیٹ کریں", "AOSP کی باکس سیٹ کریں", "کسٹم فنگر پرنٹ سیٹ کریں", "GMS پروسیس کو ختم کریں", "PIF SDK کو سپوف کریں", "ٹرکی پیچ کو سپوف کریں", "SusFS کنفگ کو اپ ڈیٹ کریں", "پابندی شدہ کی باکس کی فہرست", "GMS سپوفنگ کو غیر فعال کریں", "GMS سپوفنگ کو فعال کریں", "ڈیوائس تصدیق شدہ نہیں ہے درست کریں", "غیر معمولی کھوج", "نشان زد ایپس", "پراپس کھوج", "ماڈیول کی معلومات", "مسئلہ کی اطلاع دیں", "مدد گروپ", "اپ ڈیٹ چینل"],
      vi: ["Tắt chế độ danh sách trắng tự động", "Bật chế độ danh sách trắng tự động", "Nhắm mục tiêu tất cả ứng dụng", "Nhắm mục tiêu ứng dụng người dùng", "Đặt Hộp khóa hợp lệ", "Đặt Hộp khóa AOSP", "Đặt vân tay tùy chỉnh", "Dừng tiến trình GMS", "Giả mạo PIF SDK", "Giả mạo bản vá Tricky", "Cập nhật cấu hình SusFS", "Danh sách Hộp khóa bị cấm", "Tắt giả mạo GMS", "Bật giả mạo GMS", "SỬA: thiết bị chưa được chứng nhận", "Phát hiện bất thường", "Ứng dụng bị gắn cờ", "Phát hiện thuộc tính", "Thông tin mô-đun", "Báo cáo sự cố", "Nhóm trợ giúp", "Kênh cập nhật"]
    };

    const buttonGroups = {
      "System & Toggles": { en: "System & Toggles", ru: "Система и Переключатели", uk: "Система та Перемикачі", id: "Sistem & Pengalih", pl: "System i Przełączniki", hi: "सिस्टम और टॉगल", te: "సిస్టమ్ & టోగుల్స్", ta: "கணினி & மாற்றிகள்", es: "Sistema y Conmutadores", bn: "সিস্টেম এবং টগল", pt: "Sistema e Alternadores", zh: "系统和切换", fr: "Système et Bascules", ar: "النظام والمفاتيح", ur: "سسٹم اور ٹوگلز", vi: "Hệ thống & Chuyển đổi" },
      "Spoofing & Patching": { en: "Spoofing & Patching", ru: "Спуфинг и Патчи", uk: "Спуфінг та Патчі", id: "Spoofing & Penambalan", pl: "Fałszowanie i Łatanie", hi: "स्पूफिंग और पैचिंग", te: "స్పూఫింగ్ & ప్యాచింగ్", ta: "ஏமாற்றுதல் & ஒட்டுதல்", es: "Falsificación y Parcheo", bn: "স্পুফিং এবং প্যাচিং", pt: "Falsificação e Correção", zh: "伪装与修补", fr: "Falsification et Patch", ar: "التزييف والتصحيح", ur: "سپوفنگ اور پیچنگ", vi: "Giả mạo & Vá lỗi" },
      "Diagnostics": { en: "Diagnostics", ru: "Диагностика", uk: "Діагностика", id: "Diagnostik", pl: "Diagnostyka", hi: "निदान", te: "డయాగ్నోస్టిక్స్", ta: "நோய் கண்டறிதல்", es: "Diagnósticos", bn: "ডায়াগনস্টিকস", pt: "Diagnósticos", zh: "诊断", fr: "Diagnostics", ar: "التشخيص", ur: "تشخیص", vi: "Chẩn đoán" },
      "Community & Info": { en: "Community & Info", ru: "Сообщество и Информация", uk: "Спільнота та Інфо", id: "Komunitas & Info", pl: "Społeczność i Informacje", hi: "समुदाय और जानकारी", te: "సంఘం & సమాచారం", ta: "சமூகம் & தகவல்", es: "Comunidad e Información", bn: "সম্প্রদায় এবং তথ্য", pt: "Comunidade e Informações", zh: "社区与信息", fr: "Communauté et Informations", ar: "المجتمع والمعلومات", ur: "کمیونٹی اور معلومات", vi: "Cộng đồng & Thông tin" }
    };

    langDropdown.addEventListener("change", () => {
      const lang = langDropdown.value;
      document.documentElement.setAttribute("dir", lang === "ar" || lang === "ur" ? "rtl" : "ltr");

      document.querySelectorAll(".group-title").forEach(title => {
        const originalKey = title.dataset.key || title.textContent;
        if (!title.dataset.key) title.dataset.key = originalKey;
        if (buttonGroups[originalKey] && buttonGroups[originalKey][lang]) {
          title.textContent = buttonGroups[originalKey][lang];
        }
      });

      const buttonLabels = translations[lang] || translations["en"];
      const buttonOrder = ["stop.sh", "start.sh", "systemuser.sh", "user.sh", "keybox.sh", "aosp.sh", "pif.sh", "kill.sh", "spoof.sh", "patch.sh", "sus.sh", "banned.sh", "setprop.sh", "resetprop.sh", "vending.sh", "abnormal.sh", "app.sh", "prop.sh", "info.sh", "issue.sh", "meowverse.sh", "meowdump.sh"];

      buttonOrder.forEach((scriptName, index) => {
        const btn = document.querySelector(`.btn[data-script='${scriptName}']`);
        if (btn) {
          const icon = btn.querySelector('.icon');
          const spinner = btn.querySelector('.spinner');
          const label = buttonLabels[index] || btn.textContent.replace(/<[^>]*>/g, "").trim();
          btn.innerHTML = '';
          if (icon) btn.appendChild(icon);
          btn.appendChild(document.createTextNode(label));
          if (spinner) btn.appendChild(spinner);
        }
      });
    });
  }

  const toggle = document.getElementById("theme-toggle");
  toggle.checked = true;
  document.documentElement.classList.add("dark");
  localStorage.setItem("theme", "dark");
});