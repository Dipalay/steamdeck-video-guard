#!/usr/bin/env python3
"""
Steam Deck Video Guard v2 (Clean DPM Governor)
Prevents APU brownouts, GPU lockups, and VCN driver timeouts during video playback/editing.

How it works:
- When video decoding (VCN) or video editing (Kdenlive/melt, VLC, OBS, Chrome) is detected,
  it sets GPU power_dpm_force_performance_level to 'profile_standard' (stable 1100MHz).
- This eliminates the 200MHz low-voltage C-state droop (brownout) under high-FPS bursts.
- ZERO SMU sensor polling spam: does NOT spam in0_input/power1_input, completely preventing
  microcontroller mailbox congestion or bus deadlocks.
- Automatically reverts to 'auto' 5 seconds after playback stops.
"""

import os
import sys
import time
import signal

DRM_DEV = "/sys/class/drm/card0/device"
VCN_BUSY_PATH = os.path.join(DRM_DEV, "vcn_busy_percent")
PERF_LEVEL_PATH = os.path.join(DRM_DEV, "power_dpm_force_performance_level")

# Video creation, playback, and streaming applications
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
                # Elevate to profile_standard (1100 MHz stable floor)
                active_cooldown = 10  # 5 seconds cooldown after stopping
                set_gpu_profile("profile_standard")
                time.sleep(0.5)
            elif active_cooldown > 0:
                # Cooldown phase
                active_cooldown -= 1
                time.sleep(0.5)
            else:
                # Completely idle: restore auto power savings
                set_gpu_profile("auto")
                time.sleep(2.0)
    finally:
        restore_power_dpm()

if __name__ == "__main__":
    main()
