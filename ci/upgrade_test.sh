#!/bin/bash
# Install an older release, open it, then install the newest over it and
# open again: catches crashes that only happen when updating.
set +e
{
  echo "OLD: $(ls old/*.apk)"; adb install old/*.apk 2>&1
  adb shell monkey -p com.rashad.moneytracker -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 20
  adb shell pidof com.rashad.moneytracker && echo OLD_RUNNING || echo OLD_NOT_RUNNING
  adb shell am force-stop com.rashad.moneytracker
  echo "NEW: $(ls new/*.apk)"; adb install -r new/*.apk 2>&1
  adb logcat -c
  adb shell monkey -p com.rashad.moneytracker -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 25
  adb shell pidof com.rashad.moneytracker && echo RUNNING || echo NOT_RUNNING
} > run.txt 2>&1
adb logcat -d > logcat.txt 2>&1
grep -n -E "FATAL|AndroidRuntime|E flutter|Caused by" logcat.txt | head -200 > crash.txt
adb exec-out screencap -p > screen.png
exit 0
