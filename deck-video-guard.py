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
    if val.isdigit() and int(val) > 0:
        return True
    return False

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
    """Polls the SMU registers to prevent deep C-state voltage droop and fence timeouts."""
    _ = read_val(VCN_BUSY_PATH)
    _ = read_val(SCLK_PATH)
    _ = read_val(VCLK_PATH)
    _ = read_val(IN0_PATH)
    _ = read_val(POWER_PATH)

def main():
    last_media_check = 0
    media_app_active = False
    active_cooldown = 0  # stay in active mode for a few seconds after video pauses

    while running:
        now = time.time()

        # Check for media applications every 3 seconds
        if now - last_media_check >= 3.0:
            media_app_active = is_media_app_running()
            last_media_check = now

        vcn_active = is_vcn_active()

        if vcn_active or media_app_active:
            # Video or media app is active!
            active_cooldown = 10  # keep active for 5 seconds after stop (10 ticks of 0.5s)
            keep_alive_pulse()
            time.sleep(0.5)
        elif active_cooldown > 0:
            active_cooldown -= 1
            keep_alive_pulse()
            time.sleep(0.5)
        else:
            # System is completely idle (no video, no editing apps)
            time.sleep(2.5)

if __name__ == "__main__":
    main()
