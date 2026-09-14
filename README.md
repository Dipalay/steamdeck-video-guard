# Steam Deck Video Guard v2 🛡️

A lightweight, automated user-space dynamic power governor for **SteamOS (Steam Deck)** that prevents APU brownouts, GPU lockups, and hard system freezes during high-framerate/high-resolution video playback (such as 1440p60 AV1 at 2x speed) and video editing.

---

## ⚡ The Problem

When playing high-bitrate video (such as YouTube 1440p60 streams at 2x speed, demanding sustained 120 FPS decode of AV1 `av01` or VP9) or scrubbing timelines in video editors (Kdenlive, Shotcut, OBS):
* SteamOS's default dynamic power management drops the GPU core clock down to its minimum sleep floor (**200 MHz**, ~155 mV).
* A sudden burst of decoding frames triggers a transient voltage sag (brownout) or Wayland compositor sync-fence timeout.
* Because the Van Gogh APU lacks isolated GPU power rails for on-the-fly hardware resets, this immediately locks up the device or cuts power (hard PMIC shutdown).

## 🚀 The Solution (v2 Dynamic DPM Governor)

`deck-video-guard` runs as an automated background daemon that monitors the hardware video decoder (VCN) and active media processes (native and Flatpak sandboxed Chrome, Kdenlive/melt, VLC, OBS, etc.):

* **Automatic DPM Powerfloor:** The moment video playback or editing starts, it automatically elevates AMDGPU's performance level to `profile_standard` (locking a stable **1100 MHz** floor). This completely eliminates the 200 MHz voltage collapse.
* **Instant Power Savings:** 5 seconds after playback or editing stops, it smoothly returns to `auto` (allowing the APU to drop back down to 200 MHz idle for maximum battery life).
* **Zero SMU Spam / Zero Deadlock Risk:** Unlike naive sensor-polling scripts, v2 uses clean, event-driven sysfs state management with zero microcontroller mailbox spam.
* **Zero Overhead:** 0.000% CPU when idle, <0.02% CPU during playback.
* **Non-Invasive:** Runs as a standard `systemd --user` service. Does **not** require `sudo`, does **not** disable the read-only SteamOS system partition, and survives SteamOS updates.

---

## 📦 Quick Installation

Open **Konsole** in Desktop Mode, paste the following command, and hit Enter:

```bash
curl -sSL https://raw.githubusercontent.com/Dipalay/steamdeck-video-guard/main/install.sh | bash
```

---

## 🔍 Verification

To verify that the service is running properly:

```bash
systemctl --user status deck-video-guard
```

You should see: `Active: active (running) (enabled)`.

---

## 🗑️ Uninstallation

If Valve natively patches this in a future SteamOS update:

```bash
curl -sSL https://raw.githubusercontent.com/Dipalay/steamdeck-video-guard/main/uninstall.sh | bash
```
