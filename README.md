<div align="center">
  <img
    src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/assets/new/meow.png"
    alt="Integrity Box Banner"
    width="85%"
    style="border-radius: 160px;"
  />
</div>


<details>
<summary><strong>FAQ</strong></summary>
  
- **What is IntegrityBox?**  
  Integrity Box started as a simple project to make keybox management easier for rooted Android users. Over time, it grew into a toolkit that brings Play Integrity fixes, system property management, spoofing controls, and other useful features together in one place. The project continues to evolve as Android changes, with new features, fixes, and improvements added along the way.

- **IDK how to use this module?**
  > **Fresh installation only:** After flashing the module, **do not reboot immediately**. Go back to your root manager's **Modules** section, launch the WebUI, and configure the module first. Once you're done, reboot your device to apply the changes. This setup UI appears only after a fresh installation and is different from the regular WebUI.
  >
  > [Click here to see the setup UI.](https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/assets/new/Configuration.png)

  _Just flash the module and forget about it. Integrity Box handles the rest, so you don't have to mess with configuration files or run commands manually._

  _Magisk users need to [install this app](https://github.com/MeowDump/KsuWebUIStandalone/releases) to access the WebUI._

- **Does IntegrityBox replace Play Integrity Fix/Fork module?**  
  Yes! Starting from v28, PIF is fully integrated into IntegrityBox. The module ID was changed to `playintegrityfix` when i updated the [module base](https://github.com/MeowDump/Integrity-Box/blob/931f1dd91cc785c4ab95bf3e049acf7f0e71bb77/module.prop). IntegrityBox now handles everything PIF did so installing PIF module is does not make any sense.

- **Do I need to install Tricky Addon or PIF module**  
  **NO,** Please read the requirements section below.
  
#
</details>


<details>
<summary><strong>Requirements</strong></summary>

> Please make sure you have the following **modules installed** before using Integrity Box:

1) - [**Tricky Store OOS**](https://github.com/beakthoven/TrickyStoreOSS/releases) or [**TEE Simulator**](https://github.com/JingMatrix/TEESimulator/releases) (use any one) 

2) - [**Zygisk Next**](https://github.com/LSPosed/ZygiskNext/releases) or [**Meow Zygisk**](https://github.com/MeowDump/MeowZygisk/releases) (use any one) 


- _If you are using Google Pixel stock ROM, or if you want to use your custom ROM's inbuilt spoofing feature, you do not need Zygisk. Simply create a file or folder named `zygisk` in your internal storage `/sdcard/zygisk` (make sure the name is exactly lowercase), and then flash Integrity Box. This will disable all zygisk related components and grant you full CONTROL without any conflict_

#
</details>


<details>
<summary><strong>Troubleshooting</strong></summary>

If Play Integrity is failing, go through the following common causes and try the suggested solutions.

### 1. Check Your Keybox

An invalid or revoked keybox may prevent Play Integrity from passing.

**What to do:** Check your keybox status using the [Keybox Integrity Status UI](https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/assets/new/KEY-STATUS.png).

**Note:** A valid keybox does not guarantee that Play Integrity will pass. Play Protect now checks few more things, for more details, read the Device Certification section of this page.

### 2. Try Repair Mode

If your keybox is valid but Play Integrity is still failing, try the built-in repair tool.

**What to do:** Open **WebUI --> Repair Mode --> Repair**.

### 3. ROM-Level GMS Spoofing

Some custom ROMs include built-in spoofing for Google Play Services (GMS) and the Play Store. This can conflict with Integrity Box's own spoofing and cause Play Integrity to fail.

**What to do:**

1. Open your ROM settings and look for **Miscellaneous --> Spoofing / Play Integrity**. The menu names may vary depending on your ROM.
2. If available, disable the ROM's built-in spoofing.
3. If your ROM does not provide an option to disable it (for example, PixelOS), open **Integrity Box WebUI --> ROM Spoofing**.
4. Click **DISABLE DEVICE SPOOFING** and **DISABLE PLAYSTORE SPOOFING**.
5. Reboot your device and check Play Integrity again.

### 4. Check SELinux Status

SELinux should ideally be in `ENFORCING` mode. If it shows `PERMISSIVE`, consider switching to a ROM that supports enforcing mode.

You can check your SELinux status in the Integrity Box WebUI using these screenshots:

[Dashboard](https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/assets/new/GUIDE-DASHBOARD.png) --> [SELinux Status](https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/assets/new/GUIDE-SELINUX.png)

**Alternative (not recommended):** Open **WebUI → Module Settings**, enable **Spoof SELinux**, and reboot your device.

> **Warning:** This option may cause boot issues. If your device fails to boot, remove `/data/adb/Box-Brain/spoof-selinux-boot` from recovery. _I’m giving you a sharp knife, use it carefully. If something goes wrong, let’s just call it a **skill issue**._

### 5. Conflicting Modules

Other Magisk, KernelSU, or LSPosed modules may interfere with Integrity Box, especially those that modify GMS, Zygisk, Play Integrity, or device properties.

**What to do:** Temporarily disable other related modules, reboot, and test again.

For a basic setup, you only need Zygisk, Integrity Box, and Tricky Store. Additional modules may cause conflicts.

### 6. Google Play Services Update

A recent Google Play Services update may be related to Play Integrity failures.

**What to do:** If the problem started after an update, try uninstalling Google Play Services updates from Android Settings, if available, and test again.

### 7. Check Your Device Fingerprint

An invalid or banned device fingerprint can cause Play Integrity to fail.

**What to do:** WebUI --> Set Profile --> choose `PIXELIFY` or `SUPREME` profile

#
</details>


<details>
<summary><strong>Device Certification</strong></summary>

## Solutions for FIX DEVICE NOT CERTIFIED error in PlayStore
> Note: Your device must pass at least `DEVICE INTEGRITY` to meet the required certification checks.

### 1. Lock bootloader to fix issue

> Google detects your unlocked bootloader.

You can try using **Tricky Store OOS** with a valid keybox to address this without locking your bootloader.

### 2. Reset device to fix issue

> Play Protect is detecting root on your device.

Make sure root is properly hidden to resolve this issue.

### 3. We recommend checking for and installing the latest system updates for your device

> Your device's security patch is outdated.

You can spoof the android system security patch using Integrity Box. However, this may cause issues on some stock ROMs.

**How to enable patch spoofing:** Open **WebUI --> Module Settings**, disable the `Skip Patch Spoofing` toggle, and reboot your device.

### 4. There was an issue found with your device

> Your device failed Play Protect certification checks.

This happens when one or more of the following are detected:

- Unlocked bootloader
- Custom ROM
- Root

Address the cause to resolve the certification issue.

### 5. Something went wrong. Try again later

> Google Play Services is updating in the background.

Wait for the update to finish, then try again.

#
</details>


<details>
<summary><strong>Report a Problem</strong></summary>
  
- `WebUI` >> `Report a Problem` >> `Export Report`
- An archive (.tar.gz) file will be generated inside `/sdcard/MeowLog` folder
- Share that file to [𝗠𝗘𝗢𝗪𝗻𝗮 💅](https://t.me/HelloMona) and explain your problem in detail. 
#
</details>

<details>
<summary><strong>Acknowledgement</strong></summary>
  
#### This project uses code from the following external open-source work:
- [ezme-nodebug](https://github.com/ez-me/ezme-nodebug)
- [PlayIntegrityFix](https://github.com/KOWX712/PlayIntegrityFix) & [PlayIntegrityFork](https://github.com/osm0sis/PlayIntegrityFork)
#
</details>


<p align="center">
  <img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/footers/gray0_ctp_on_line.svg?sanitize=true" alt="Catppuccin Footer" />
</p>

<div align="center">
  <a href="https://github.com/MeowDump/Integrity-Box/releases" target="_blank">
    <img src="https://github.com/MeowDump/Integrity-Box/blob/main/assets/new/BUTTON-Download.png" alt="Download Button" width="400">
  </a>
</div>

<br>

<div align="center" style="display: flex; justify-content: center; gap: 40px; flex-wrap: nowrap;">
  <a href="https://t.me/MeowDump" target="_blank">
    <img src="https://github.com/MeowDump/Integrity-Box/blob/main/assets/new/BUTTON-Telegram.png" width="150" alt="Telegram Group">
  </a>
  <a href="https://MeowDump.github.io" target="_blank">
    <img src="https://github.com/MeowDump/Integrity-Box/blob/main/assets/new/BUTTON-donate.png" width="150" alt="Donate">
  </a>
  <a href="https://t.me/integritybox" target="_blank">
    <img src="https://github.com/MeowDump/Integrity-Box/blob/main/assets/new/BUTTON-keybox.png" width="150" alt="Get Keybox">
  </a>
</div>

-

<p align="center">
  <a href="https://github.com/MeowDump/Integrity-Box/stargazers">
    <img 
      src="https://m3-markdown-badges.vercel.app/stars/7/1/MeowDump/Integrity-Box" 
      alt="GitHub Stars" 
    />
  </a>
  <br />
  <a href="https://github.com/MeowDump/Integrity-Box/releases">
    <img 
      src="https://img.shields.io/github/downloads/MeowDump/Integrity-Box/total?label=Downloads%20%28excluding%20telegram%20release%29&color=%23ff1493&style=flat" 
      alt="GitHub Releases" 
    />
  </a>
</p>

## Features at a Glance  
  Every UI includes an info button that explains the available options and how they work. Just [click on the info button](https://raw.githubusercontent.com/MeowDump/Integrity-Box/02f840aaff50c5d071481cda22a614e81f8fbd7a/assets/new/GUIDE-INFO-BTN1.png) to learn more. [Click here](https://raw.githubusercontent.com/MeowDump/Integrity-Box/02f840aaff50c5d071481cda22a614e81f8fbd7a/assets/new/GUIDE-INFO-BTN2.png) to see an example.
  
<table align="center">
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/HOME.png" alt="Home" width="260" /><br/>Home</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/HOME2.png" alt="Home Preview 2" width="260" /><br/>Home</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/HOME3.png" alt="Home Preview 3" width="260" /><br/>Home</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/DASHBOARD.png" alt="Dashboard" width="260" /><br/>Dashboard</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/INTERFACE.png" alt="Interface" width="260" /><br/>Interface</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/LOGS.png" alt="Logs" width="260" /><br/>Logs</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/CONTROL-CENTRE1.png" alt="Control Centre" width="260" /><br/>Module Settings</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/CONTROL-CENTRE2.png" alt="Control Centre Profile" width="260" /><br/>Module Settings</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/CONTROL-CENTRE3.png" alt="Control Centre Key Loader" width="260" /><br/>Module Settings</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/KEY-LOADER1.png" alt="Key Loader" width="260" /><br/>Keybox Loader</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/KEY-LOADER2.png" alt="Key Loader Options" width="260" /><br/>Keybox Loader</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/KEY-LOADER3.png" alt="Key Loader Interface" width="260" /><br/>Keybox Loader</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/KEY-SOURCE.png" alt="Key Source" width="260" /><br/>Multiple Keybox Source</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/BOOT-HASH.png" alt="Boot Hash" width="260" /><br/>Fix Boot Hash</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/DEV-MODE.png" alt="Developer Mode" width="260" /><br/>Developer Mode</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/PROP-SPOOFER.png" alt="Property Spoofer" width="260" /><br/>Prop Spoofer</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/BL-SPOOFER.png" alt="Bootloader Spoofer" width="260" /><br/>Bootloader Spoofer</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/ROM-SPOOFING.png" alt="ROM Spoofing" width="260" /><br/>Disable ROM Spoofing</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/PER-APP-SPOOFING.png" alt="Per-App Spoofing" width="260" /><br/>Per-App Spoofing</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/AUTO-PILOT.png" alt="Auto Pilot" width="260" /><br/>Auto Update Keybox</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/DOWNLOADER.png" alt="Downloader" width="260" /><br/>Built-in Downloader</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/CONFLICT-RESOLVER.png" alt="Conflict Resolver" width="260" /><br/>Conflict Resolver</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/REPAIR-MODE.png" alt="Repair Mode" width="260" /><br/>Integrity Repair Mode</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/HIDE-SUS.png" alt="Hide SUS" width="260" /><br/>Hide SUS</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/PROFILE.png" alt="Profile" width="260" /><br/>Integrity Profile</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/ASSISTANT.png" alt="Assistant" width="260" /><br/>Assistant</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/HELP-REPORT.png" alt="Help and Reports" width="260" /><br/>Help and Reports</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/TRANSLATION.png" alt="Translations" width="260" /><br/>Translations</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/refs/heads/main/assets/new/ACTION.png" alt="Action" width="260" /><br/>Action</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/KEY-ATTEST.png" alt="Key Attestation" width="260" /><br/>Key Attestation</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/WALLET.jpg" alt="Wallet" width="260" /><br/>Wallet works</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/PLAY-INTEGR.png" alt="Play Integrity" width="260" /><br/>Play Integrity will pass</td>
    <td align="center"><img src="https://raw.githubusercontent.com/MeowDump/Integrity-Box/main/assets/new/RCS.jpg" alt="RCS" width="260" /><br/>RCS Works</td>
  </tr>
</table>
