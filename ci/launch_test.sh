#!/bin/bash
set +e
APK=$(ls *.apk | head -1)
{
  echo "APK: $APK"
  adb install -r "$APK" 2>&1
  adb logcat -c
  adb shell monkey -p com.rashad.moneytracker -c android.intent.category.LAUNCHER 1 2>&1
  sleep 30
  adb shell pidof com.rashad.moneytracker && echo RUNNING || echo NOT_RUNNING
} > run.txt 2>&1
adb logcat -d > logcat.txt 2>&1
grep -n -E "FATAL|AndroidRuntime|E flutter|Exception|Caused by" logcat.txt | head -200 > crash.txt
adb exec-out screencap -p > screen.png
exit 0
