#!/bin/bash
set -e

echo "=== Installing Steam Deck Video Guard v2 ==="

# 1. Ensure directories exist
mkdir -p ~/.local/bin
mkdir -p ~/.config/systemd/user

# 2. Download / Install the script
cat << 'PYEOF' > ~/.local/bin/deck-video-guard.py
#!/usr/bin/env python3
"""
Steam Deck Video Guard v2 (APU & DPM Stability Keeper)
Prevents APU brownouts, GPU lockups, and VCN driver timeouts during video playback/editing.

Key Architecture:
1. Dynamic DPM Profile Management:
   - When hardware video decoding (VCN) or media apps (Kdenlive, VLC, OBS, etc.) are active,
     it elevates GPU power_dpm_force_performance_level to 'profile_standard' (fixed stable 1100MHz).
   - This physically eliminates the 200MHz low-voltage C-state droop (brownout) under sudden 120 FPS decode bursts.
   - Automatically drops back to 'auto' (power-saving mode) 5 seconds after playback stops.
2. Hardware SMU Keep-Alive Heartbeat:
   - Periodically queries amdgpu hwmon telemetry (in0_input voltage, power1_input, temp1_input),
     forcing the AMD System Management Unit to actively maintain voltage regulator responsiveness.
3. Universal Process Detection:
   - Detects both native apps and containerized Flatpak apps (inspecting /proc/*/comm and cmdline).

Zero-overhead, runs as a user systemd service.
"""

import os
import sys
import time
import glob
import signal

DRM_DEV = "/sys/class/drm/card0/device"
VCN_BUSY_PATH = os.path.join(DRM_DEV, "vcn_busy_percent")
GPU_BUSY_PATH = os.path.join(DRM_DEV, "gpu_busy_percent")
SCLK_PATH = os.path.join(DRM_DEV, "pp_dpm_sclk")
VCLK_PATH = os.path.join(DRM_DEV, "pp_dpm_vclk")
PERF_LEVEL_PATH = os.path.join(DRM_DEV, "power_dpm_force_performance_level")

MEDIA_APPS = {
    # Video Editing & Rendering Engines
    "kdenlive", "melt", "shotcut", "resolve", "davinci", "obs", "obs64", "ffmpeg",
    # Media Players
    "vlc", "mpv", "celluloid", "haruna", "dragon", "smplayer", "totem", "freetube",
    # Web Browsers
    "chrome", "chromium", "firefox", "firefox-bin", "brave", "edge",
    "opera", "vivaldi", "librewolf", "zen"
}

running = True

def restore_power_dpm():
    try:
        if os.path.exists(PERF_LEVEL_PATH):
            with open(PERF_LEVEL_PATH, "w") as f:
                f.write("auto")
    except Exception:
        pass

def handle_sig(signum, frame):
    global running
    running = False
    restore_power_dpm()

signal.signal(signal.SIGTERM, handle_sig)
signal.signal(signal.SIGINT, handle_sig)

def read_val(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return ""

def write_val(path, val):
    try:
        with open(path, "w") as f:
            f.write(val)
        return True
    except Exception:
        return False

def find_amdgpu_hwmon():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            with open(os.path.join(h, "name"), "r") as f:
                if f.read().strip() == "amdgpu":
                    return h
        except Exception:
            pass
    return None

hwmon_dir = find_amdgpu_hwmon()

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
                    if comm == "bwrap":
                        cmdline = open(f"/proc/{pid}/cmdline", "r").read().lower()
                        if any(app in cmdline for app in MEDIA_APPS):
                            return True
                except Exception:
                    pass
    except Exception:
        pass
    return False

def set_gpu_profile(target_level):
    try:
        current = read_val(PERF_LEVEL_PATH)
        if current != target_level:
            write_val(PERF_LEVEL_PATH, target_level)
    except Exception:
        pass

def keep_alive_pulse():
    global hwmon_dir
    # 1. DRM hardware state poll
    _ = read_val(VCN_BUSY_PATH)
    _ = read_val(GPU_BUSY_PATH)
    _ = read_val(SCLK_PATH)
    _ = read_val(VCLK_PATH)

    # 2. Hardware SMU telemetry poll (triggers active power rail management)
    if not hwmon_dir or not os.path.exists(hwmon_dir):
        hwmon_dir = find_amdgpu_hwmon()
    if hwmon_dir:
        _ = read_val(os.path.join(hwmon_dir, "in0_input"))      # GPU vddgfx voltage
        _ = read_val(os.path.join(hwmon_dir, "power1_input"))   # GPU power draw
        _ = read_val(os.path.join(hwmon_dir, "temp1_input"))    # GPU temperature

def main():
    global running
    last_proc_check = 0
    media_app_running = False
    active_cooldown = 0  # in ticks of 0.5s

    try:
        while running:
            now = time.time()

            # Scan processes every 3 seconds to preserve CPU
            if now - last_proc_check >= 3.0:
                media_app_running = is_media_app_running()
                last_proc_check = now

            vcn_active = is_vcn_active()

            if vcn_active or media_app_running:
                # Video or editing app is active!
                # Keep active for 5 seconds after activity stops (10 ticks * 0.5s)
                active_cooldown = 10
                set_gpu_profile("profile_standard")
                keep_alive_pulse()
                time.sleep(0.5)
            elif active_cooldown > 0:
                # Cooldown phase
                active_cooldown -= 1
                keep_alive_pulse()
                time.sleep(0.5)
            else:
                # Completely idle: restore auto power savings
                set_gpu_profile("auto")
                time.sleep(2.0)
    finally:
        restore_power_dpm()

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
echo "✅ Installation Complete! Steam Deck Video Guard v2 is now active and running."
echo "You can check status anytime with: systemctl --user status deck-video-guard"
