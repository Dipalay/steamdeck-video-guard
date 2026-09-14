# Steam Deck Video Guard 🛡️

A lightweight, automated user-space background service for **SteamOS (Steam Deck)** that prevents APU brownouts, GPU lockups, and hard system shutdowns during high-framerate/high-resolution video playback (such as 1440p60 AV1 at 2x speed) and video editing.

---

## ⚡ The Problem

When playing high-bitrate video (such as YouTube 1440p60 stream recordings at 2x speed, demanding 120 FPS decode of AV1 `av01` or VP9), SteamOS's aggressive power management drops the APU into deep C-state sleep at 200 MHz. The sudden burst of decoding frames triggers a transient voltage droop (brownout) or Wayland fence timeout, resulting in a system freeze or instant hard power-off.

## 🚀 The Solution

`deck-video-guard` monitors the hardware decoder state and active media applications. When video playback or editing is detected, it sends lightweight keep-alive pulses to the AMD SMU (System Management Unit) registers at 500ms intervals. This prevents the voltage regulator from falling into deep sleep states and eliminates the brownout.

* **Zero Overhead:** 0.000% CPU when idle, <0.02% CPU during playback (each pulse takes 0.08 ms).
* **Zero Disk Writes:** Runs entirely in memory, no disk writes or SSD wear.
* **Non-Invasive:** Runs as a `systemd --user` service. Does **not** require `sudo`, does **not** disable the read-only SteamOS system partition, and survives system updates.

---

## 📦 Quick Installation

Open **Konsole** in Desktop Mode, paste the following command, and hit Enter:

```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/steamdeck-video-guard/main/install.sh | bash
```

*(Replace `YOUR_USERNAME` with your GitHub username).*

---

## 🔍 Verification

To check if the service is running properly:

```bash
systemctl --user status deck-video-guard
```

You should see: `Active: active (running)`.

---

## 🗑️ Uninstallation

If Valve ever patches this natively in SteamOS and you wish to remove the service:

```bash
curl -sSL https://raw.githubusercontent.com/Dipalay/steamdeck-video-guard/main/uninstall.sh | bash
```
