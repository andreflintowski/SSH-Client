#!/bin/bash
# Installs SSH.apk on the running emulator, opens it and saves what it shows and logs.
log() { echo "$*" >> steps.txt; }
log "install: $(adb install -r SSH.apk 2>&1 | tail -1)"
adb logcat -c
log "launch: $(adb shell monkey -p dev.andre.ssh_client -c android.intent.category.LAUNCHER 1 2>&1 | tail -1)"
sleep 40
adb logcat -d > logcat.txt 2>&1
adb shell dumpsys window 2>&1 | grep -E 'mCurrentFocus|mFocusedApp' > focus.txt
adb shell pidof dev.andre.ssh_client > pid.txt 2>&1 || echo none > pid.txt
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml > ui.txt 2>&1
exit 0
