const MODDIR = "/data/adb/modules/Integrity-Box";
const PROP = `${MODDIR}/module.prop`;

function isMMRL() {
  return navigator.userAgent.includes("com.dergoogler.mmrl");
}

function runShell(command) {
  if (isMMRL()) return Promise.reject("Not compatible with MMRL. Use KSUWebUI.");
  if (typeof ksu !== "object" || typeof ksu.exec !== "function")
    return Promise.reject("KernelSU JavaScript API not available.");
  const cb = `cb_${Date.now()}`;
  return new Promise((resolve, reject) => {
    window[cb] = (code, stdout, stderr) => {
      delete window[cb];
      code === 0 ? resolve(stdout) : reject(stderr || "Shell error");
    };
    ksu.exec(command, "{}", cb);
  });
}

function popup(msg) {
  return runShell(`am start -a android.intent.action.MAIN -e mona "${msg}" -n meow.helper/.MainActivity`);
}

async function getModuleName() {
  try {
    const name = await runShell(`grep '^name=' ${PROP} | cut -d= -f2`);
    document.getElementById("module-name").textContent = name.trim();
    document.title = name.trim();
  } catch {
    document.getElementById("module-name").textContent = "Integrity-Box";
  }
}

document.addEventListener("DOMContentLoaded", () => {
  getModuleName();

  document.querySelectorAll(".btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const script = btn.dataset.script;
      runShell(`sh ${MODDIR}/${script}`);
    });
  });

  const toggle = document.getElementById("theme-toggle");
  const saved = localStorage.getItem("theme");
  if (saved === "dark") {
    document.documentElement.classList.add("dark");
    toggle.checked = true;
  }

  toggle.addEventListener("change", () => {
    document.documentElement.classList.toggle("dark", toggle.checked);
    localStorage.setItem("theme", toggle.checked ? "dark" : "light");
  });

  const translations = {
    en: ["Add All Apps in Target list", "Add Only User Apps in Target list", "Set Valid Keybox", "Set AOSP Keybox", "Set Custom Fingerprint", "Kill GMS Process", "Spoof PIF SDK", "Update TrickyStore Security Patch File", "Add custom rom detection files into SusFS Config", "Banned Keybox List", "Disable inbuilt GMS Spoofing", "Enable inbuilt GMS Spoofing", "FIX Device is not Certified", "Scan for Abnormal Detection", "Scan for harmful Apps", "Scan for Props Detection", "Module Info", "Report a Problem", "Join Help Group", "Join Update Channel"],
    id: ["Tambahkan semua aplikasi ke daftar target", "Tambahkan hanya aplikasi pengguna", "Setel Keybox yang valid", "Setel Keybox AOSP", "Setel sidik jari kustom", "Matikan proses GMS", "Spoof PIF SDK", "Perbarui file patch TrickyStore", "Tambahkan file deteksi ROM ke konfigurasi SusFS", "Daftar Keybox yang diblokir", "Nonaktifkan spoofing GMS", "Aktifkan spoofing GMS", "PERBAIKI perangkat tidak bersertifikat", "Pindai deteksi abnormal", "Pindai aplikasi berbahaya", "Pindai deteksi properti", "Info Modul", "Laporkan masalah", "Gabung grup bantuan", "Gabung saluran pembaruan"],
    pl: ["Dodaj wszystkie apki do listy", "Dodaj tylko apki użytkownika", "Ustaw nieodwołany keybox", "Ustaw keybox AOSP", "Ustaw własny PIF", "Zabij proces GMS", "Sfałszuj PIF SDK", "Zaktualizuj plik łatki TrickyStore", "Dodaj pliki detekcji custom ROM do SusFS", "Zbanowane keyboxy", "Wyłącz podszywanie w GMS", "Włącz podszywanie w GMS", "Napraw brak certyfikatu", "Skanuj niezamaskowane apki", "Skanuj szkodliwe apki", "Skanuj wykrycie właściwości", "Informacje o module", "Zgłoś problem", "Dołącz do grupy pomocy", "Dołącz do kanału aktualizacji"],
    ru: ["Добавить все приложения в список", "Добавить только пользовательские приложения", "Установить действительный Keybox", "Установить AOSP Keybox", "Установить пользовательский отпечаток", "Завершить процесс GMS", "Спуфинг PIF SDK", "Обновить файл безопасности TrickyStore", "Добавить файлы обнаружения ROM в SusFS", "Список запрещенных Keybox", "Отключить GMS Spoofing", "Включить GMS Spoofing", "ИСПРАВИТЬ: устройство не сертифицировано", "Сканировать на аномалии", "Сканировать вредоносные приложения", "Сканировать Props", "Информация о модуле", "Сообщить о проблеме", "Присоединиться к группе поддержки", "Подписаться на канал обновлений"],
    hi: ["सभी ऐप्स को सूची में जोड़ें", "केवल उपयोगकर्ता ऐप्स जोड़ें", "वैध कीबॉक्स सेट करें", "AOSP कीबॉक्स सेट करें", "कस्टम फिंगरप्रिंट सेट करें", "GMS प्रक्रिया समाप्त करें", "PIF SDK को स्पूफ करें", "ट्रिकी स्टोर की पैच स्पूफिंग अपडेट करें", "SusFS में कस्टम रोम डिटेक्शन जोड़ें", "प्रतिबंधित कीबॉक्स सूची", "GMS स्पूफिंग बंद करें", "GMS स्पूफिंग चालू करें", "डिवाइस प्रमाणन ठीक करें", "असामान्य गतिविधि स्कैन करें", "हानिकारक ऐप्स स्कैन करें", "प्रॉप्स डिटेक्शन स्कैन करें", "मॉड्यूल जानकारी", "समस्या रिपोर्ट करें", "सहायता समूह से जुड़ें", "अपडेट चैनल से जुड़ें"],
    te: ["అన్ని యాప్స్ జాబితాలో చేర్చండి", "వినియోగదారు యాప్స్ మాత్రమే చేర్చండి", "చెల్లుబాటు అయ్యే Keybox సెట్ చేయండి", "AOSP Keybox సెట్ చేయండి", "కస్టమ్ ఫింగర్ ప్రింట్ సెట్ చేయండి", "GMS ప్రాసెస్‌ను ముగించండి", "PIF SDK స్పూఫ్ చేయండి", "TrickyStore ఫైల్‌ను అప్‌డేట్ చేయండి", "SusFS కాన్ఫిగ్‌లో డిటెక్షన్ ఫైళ్ళను జోడించండి", "నిషేధిత Keybox లిస్ట్", "GMS స్పూఫింగ్ నిలిపివేయండి", "GMS స్పూఫింగ్ ప్రారంభించండి", "సర్టిఫికేషన్ ఫిక్స్ చేయండి", "అసాధారణ డిటెక్షన్ స్కాన్ చేయండి", "హానికరమైన యాప్‌లను స్కాన్ చేయండి", "Props డిటెక్షన్ స్కాన్ చేయండి", "మాడ్యూల్ సమాచారం", "సమస్యను నివేదించండి", "హెల్ప్ గ్రూప్‌లో చేరండి", "అప్‌డేట్ ఛానెల్‌లో చేరండి"],
    ta: ["அனைத்து பயன்பாடுகளையும் சேர்க்கவும்", "பயனர் பயன்பாடுகளை மட்டும் சேர்க்கவும்", "சரியான Keybox அமைக்கவும்", "AOSP Keybox அமைக்கவும்", "விருப்பமான விரல் ரேகை அமைக்கவும்", "GMS செயலியை நிறுத்தவும்", "PIF SDK ஐ ஸ்பூஃப் செய்யவும்", "TrickyStore பாதுகாப்பு கோப்பை புதுப்பிக்கவும்", "SusFS இல் ROM கண்டறிதல் கோப்புகளை சேர்க்கவும்", "தடைசெய்யப்பட்ட Keybox பட்டியல்", "GMS Spoofing ஐ முடக்கவும்", "GMS Spoofing ஐ இயக்கவும்", "சான்றளிக்கப்படாத சாதனத்தை சரிசெய்க", "அசாதாரண கண்டறிதலை ஸ்கேன் செய்யவும்", "விழிப்புணர்வான பயன்பாடுகளை ஸ்கேன் செய்யவும்", "Props கண்டறிதலை ஸ்கேன் செய்யவும்", "தொகுதி தகவல்", "பிரச்சனையை தெரிவிக்கவும்", "உதவி குழுவில் சேரவும்", "புதுப்பிப்பு சேனலில் சேரவும்"],
    es: ["Agregar todas las apps al listado", "Agregar solo apps de usuario", "Configurar Keybox válido", "Configurar Keybox AOSP", "Configurar huella personalizada", "Finalizar proceso GMS", "Falsificar PIF SDK", "Actualizar parche de seguridad TrickyStore", "Agregar detección de ROM en SusFS", "Lista de Keybox prohibidos", "Desactivar GMS Spoofing", "Activar GMS Spoofing", "ARREGLAR dispositivo no certificado", "Escanear anormalidades", "Escanear apps dañinas", "Escanear detección de Props", "Información del módulo", "Reportar un problema", "Unirse al grupo de ayuda", "Unirse al canal de actualizaciones"],
    bn: ["সব অ্যাপ যুক্ত করুন", "শুধু ইউজার অ্যাপ যুক্ত করুন", "বৈধ Keybox সেট করুন", "AOSP Keybox সেট করুন", "কাস্টম ফিঙ্গারপ্রিন্ট সেট করুন", "GMS প্রক্রিয়া বন্ধ করুন", "PIF SDK স্পুফ করুন", "TrickyStore সুরক্ষা ফাইল আপডেট করুন", "SusFS কনফিগে ডিটেকশন ফাইল যোগ করুন", "নিষিদ্ধ Keybox তালিকা", "GMS Spoofing নিষ্ক্রিয় করুন", "GMS Spoofing সক্রিয় করুন", "অননুমোদিত ডিভাইস ঠিক করুন", "অস্বাভাবিক স্ক্যান করুন", "ক্ষতিকারক অ্যাপ স্ক্যান করুন", "Props স্ক্যান করুন", "মডিউল তথ্য", "সমস্যা রিপোর্ট করুন", "সাহায্য গ্রুপে যোগ দিন", "আপডেট চ্যানেলে যোগ দিন"],
    pt: ["Adicionar todos os apps à lista", "Adicionar apenas apps de usuário", "Definir Keybox válido", "Definir Keybox AOSP", "Definir impressão personalizada", "Finalizar processo GMS", "Falsificar PIF SDK", "Atualizar patch de segurança do TrickyStore", "Adicionar detecção de ROM no SusFS", "Lista de Keybox banidos", "Desativar GMS Spoofing", "Ativar GMS Spoofing", "CORRIGIR dispositivo não certificado", "Escanear anormalidades", "Escanear apps nocivos", "Escanear Props", "Informações do módulo", "Relatar um problema", "Entrar no grupo de ajuda", "Entrar no canal de atualizações"],
    zh: ["添加所有应用到目标列表", "只添加用户应用", "设置有效 Keybox", "设置 AOSP Keybox", "设置自定义指纹", "结束 GMS 进程", "伪装 PIF SDK", "更新 TrickyStore 安全补丁", "添加自定义 ROM 检测到 SusFS", "被封锁的 Keybox 列表", "禁用 GMS Spoofing", "启用 GMS Spoofing", "修复设备未认证问题", "扫描异常", "扫描恶意应用", "扫描 Props 检测", "模块信息", "报告问题", "加入帮助组", "加入更新频道"],
    fr: ["Ajouter toutes les apps", "Ajouter uniquement les apps utilisateur", "Définir Keybox valide", "Définir Keybox AOSP", "Définir empreinte personnalisée", "Terminer le processus GMS", "Falsifier PIF SDK", "Mettre à jour le patch TrickyStore", "Ajouter détection ROM personnalisée dans SusFS", "Liste Keybox bannis", "Désactiver le spoofing GMS", "Activer le spoofing GMS", "RÉPARER l’appareil non certifié", "Analyser les anomalies", "Analyser les apps nuisibles", "Analyser la détection Props", "Infos du module", "Signaler un problème", "Rejoindre le groupe d'aide", "Rejoindre le canal d'actualités"],
    ar: ["إضافة كل التطبيقات", "إضافة تطبيقات المستخدم فقط", "تعيين Keybox صالح", "تعيين Keybox AOSP", "تعيين بصمة مخصصة", "إنهاء عملية GMS", "تزوير PIF SDK", "تحديث ملف TrickyStore الأمني", "إضافة كشف ROM إلى SusFS", "قائمة Keybox المحظورة", "تعطيل GMS Spoofing", "تمكين GMS Spoofing", "إصلاح الجهاز غير المعتمد", "مسح للكشف غير الطبيعي", "مسح التطبيقات الضارة", "مسح كشف الخصائص", "معلومات الوحدة", "الإبلاغ عن مشكلة", "الانضمام لمجموعة الدعم", "الانضمام لقناة التحديثات"],
    ur: ["تمام ایپس شامل کریں", "صرف یوزر ایپس شامل کریں", "درست Keybox سیٹ کریں", "AOSP Keybox سیٹ کریں", "کاسٹم فنگر پرنٹ سیٹ کریں", "GMS پروسیس بند کریں", "PIF SDK کو سپوف کریں", "TrickyStore سیکیورٹی فائل اپ ڈیٹ کریں", "SusFS میں ROM کی شناخت شامل کریں", "ممنوعہ Keybox کی فہرست", "GMS Spoofing غیر فعال کریں", "GMS Spoofing فعال کریں", "غیر تصدیق شدہ ڈیوائس کو درست کریں", "غیر معمولی سکین کریں", "نقصان دہ ایپس سکین کریں", "Props سکین کریں", "ماڈیول معلومات", "مسئلہ رپورٹ کریں", "مدد گروپ میں شامل ہوں", "اپڈیٹ چینل میں شامل ہوں"]
  };

  const langDropdown = document.getElementById("lang-dropdown");
  if (langDropdown) {
    langDropdown.addEventListener("change", () => {
      const lang = langDropdown.value;
      const labels = translations[lang];
      if (!labels) return;
      document.documentElement.setAttribute("dir", lang === "ar" || lang === "ur" ? "rtl" : "ltr");
      document.querySelectorAll(".btn").forEach((btn, i) => {
        btn.textContent = labels[i] || btn.textContent;
      });
    });
  }
});
