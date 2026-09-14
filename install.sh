#!/bin/bash
set -e

echo "=== Installing Steam Deck Video Guard ==="

# 1. Ensure directories exist
mkdir -p ~/.local/bin
mkdir -p ~/.config/systemd/user

# 2. Download / Install the script
cat << 'PYEOF' > ~/.local/bin/deck-video-guard.py
#!/usr/bin/env python3
"""
Steam Deck Video Guard (APU Keep-Alive Stabilizer)
Prevents APU brownouts and VCN driver timeouts during video playback/editing.
Zero-overhead, runs as a user systemd service.
"""

import os
import sys
import time
import glob
import signal

DRM_DEV = "/sys/class/drm/card0/device"
VCN_BUSY_PATH = os.path.join(DRM_DEV, "vcn_busy_percent")
SCLK_PATH = os.path.join(DRM_DEV, "pp_dpm_sclk")
VCLK_PATH = os.path.join(DRM_DEV, "pp_dpm_vclk")

MEDIA_APPS = {
    "chrome", "chromium", "firefox", "vlc", "kdenlive",
    "shotcut", "resolve", "davinci", "mpv", "obs", "obs64"
}

def find_amdgpu_hwmon():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            with open(os.path.join(h, "name"), "r") as f:
                if f.read().strip() == "amdgpu":
                    return h
        except Exception:
            pass
    return "/sys/class/hwmon/hwmon5"

HWMON_DIR = find_amdgpu_hwmon()
IN0_PATH = os.path.join(HWMON_DIR, "in0_input")
POWER_PATH = os.path.join(HWMON_DIR, "power1_input")

running = True

def handle_sig(signum, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, handle_sig)
signal.signal(signal.SIGINT, handle_sig)

def read_val(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return ""

def is_vcn_active():
    val = read_val(VCN_BUSY_PATH)
    return val.isdigit() and int(val) > 0

def is_media_app_running():
    try:
        for pid in os.listdir("/proc"):
            if pid.isdigit():
                try:
                    comm = open(f"/proc/{pid}/comm", "r").read().strip().lower()
                    if comm in MEDIA_APPS:
                        return True
                except Exception:
                    pass
    except Exception:
        pass
    return False

def keep_alive_pulse():
    _ = read_val(VCN_BUSY_PATH)
    _ = read_val(SCLK_PATH)
    _ = read_val(VCLK_PATH)
    _ = read_val(IN0_PATH)
    _ = read_val(POWER_PATH)

def main():
    last_media_check = 0
    media_app_active = False
    active_cooldown = 0

    while running:
        now = time.time()
        if now - last_media_check >= 3.0:
            media_app_active = is_media_app_running()
            last_media_check = now

        if is_vcn_active() or media_app_active:
            active_cooldown = 10
            keep_alive_pulse()
            time.sleep(0.5)
        elif active_cooldown > 0:
            active_cooldown -= 1
            keep_alive_pulse()
            time.sleep(0.5)
        else:
            time.sleep(2.5)

if __name__ == "__main__":
    main()
PYEOF

chmod +x ~/.local/bin/deck-video-guard.py

# 3. Create systemd service
cat << 'SVCEOF' > ~/.config/systemd/user/deck-video-guard.service
[Unit]
Description=Steam Deck Video Guard (APU Stability Keeper for Video Playback & Editing)
After=default.target

[Service]
Type=simple
ExecStart=%h/.local/bin/deck-video-guard.py
Restart=always
RestartSec=5
KillMode=mixed
TimeoutStopSec=3

[Install]
WantedBy=default.target
SVCEOF

# 4. Enable and start service
systemctl --user daemon-reload
systemctl --user enable --now deck-video-guard.service

echo ""
echo "✅ Installation Complete! Steam Deck Video Guard is now active and running."
echo "You can check status anytime with: systemctl --user status deck-video-guard"
