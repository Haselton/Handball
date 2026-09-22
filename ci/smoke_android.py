"""Install the diagnostic APK and require real native SDK ad-load callbacks.

Uses only Google's sample ad units. This checks loading, not production fill,
Play Games authentication, or completed rewarded/interstitial interactions.
"""
from pathlib import Path
import re
import subprocess
import sys
import time

PACKAGE = 'com.haseltonmediagroup.handball.diagnostic'
OUT = Path('build/android/runtime')
OUT.mkdir(parents=True, exist_ok=True)
EXPECTED = ['initialized', 'banner loaded', 'interstitial loaded', 'rewarded loaded']


def adb(*args, check=True, binary=False):
    return subprocess.run(['adb', *args], check=check, capture_output=True,
                          text=not binary, timeout=30)


def main():
    adb('install', '-r', sys.argv[1])
    # On a fresh emulator, Pixel resource overlays and package configuration
    # updates continue after sys.boot_completed. They can recreate an activity
    # during Godot's initial native setup. Let those first-boot changes finish.
    print('Waiting for first-boot package and overlay configuration.', flush=True)
    time.sleep(30)
    # Suppress Android's one-time immersive-mode tutorial in the test device.
    adb('shell', 'settings', 'put', 'secure', 'immersive_mode_confirmations', 'confirmed')
    adb('logcat', '-c')
    activity = adb('shell', 'cmd', 'package', 'resolve-activity', '--brief', PACKAGE).stdout.strip().splitlines()[-1]
    if not activity.startswith(PACKAGE + '/'):
        raise RuntimeError('Diagnostic launcher activity was not found: ' + activity)
    print(adb('shell', 'am', 'start', '-W', '-n', activity).stdout, flush=True)
    deadline = time.monotonic() + 150
    app_log = ''
    pid = ''
    try:
        while time.monotonic() < deadline:
            running = adb('shell', 'pidof', PACKAGE, check=False).stdout.strip()
            if not running:
                raise RuntimeError('Handball process exited during startup')
            pid = running.split()[0]
            app_log = adb('logcat', '-d', '--pid=' + pid).stdout
            if re.search(r'SCRIPT ERROR|Parse Error|FATAL EXCEPTION|Fatal signal|E godot\s*:\s*ERROR:', app_log):
                raise RuntimeError('Android runtime reported an app error')
            if all('Handball AdMob: ' + state in app_log for state in EXPECTED):
                print('PASS: native AdMob initialized and all three test ad formats loaded.', flush=True)
                return
            time.sleep(3)
        missing = [state for state in EXPECTED if 'Handball AdMob: ' + state not in app_log]
        raise RuntimeError('Timed out waiting for native callbacks: ' + ', '.join(missing))
    finally:
        full_log = adb('logcat', '-d', check=False).stdout
        (OUT / 'emulator-logcat.txt').write_text(full_log)
        if not pid:
            started = re.search(r'Start proc (\d+):' + re.escape(PACKAGE) + r'/', full_log)
            if started:
                pid = started[1]
        if pid:
            app_log = adb('logcat', '-d', '--pid=' + pid, check=False).stdout
        (OUT / 'handball-logcat.txt').write_text(app_log)
        screenshot = adb('exec-out', 'screencap', '-p', check=False, binary=True)
        if screenshot.returncode == 0:
            (OUT / 'Handball-Android-Runtime.png').write_bytes(screenshot.stdout)
        for line in app_log.splitlines():
            if re.search(r'godot|Handball|UserMessagingPlatform|Ads\s*:', line, re.I):
                print(line)


if __name__ == '__main__':
    main()
