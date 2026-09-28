"""Makes release builds always use ci/debug.keystore, so every APK is signed
with the same key and installs over the previous version."""
import os
import re
import sys

app = "build_app/android/app"
keystore = os.path.abspath("ci/debug.keystore")
kts = os.path.join(app, "build.gradle.kts")
groovy = os.path.join(app, "build.gradle")

if os.path.exists(kts):
    path = kts
    s = open(path).read()
    block = f'''
    signingConfigs {{
        create("fixed") {{
            storeFile = file("{keystore}")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }}
    }}
'''
    s, n1 = re.subn(r'(\n\s*buildTypes\s*\{)', block + r'\1', s, count=1)
    s, n2 = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                    'signingConfig = signingConfigs.getByName("fixed")', s)
else:
    path = groovy
    s = open(path).read()
    block = f'''
    signingConfigs {{
        fixed {{
            storeFile file("{keystore}")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }}
    }}
'''
    s, n1 = re.subn(r'(\n\s*buildTypes\s*\{)', block + r'\1', s, count=1)
    s, n2 = re.subn(r'signingConfig\s+signingConfigs\.debug',
                    'signingConfig signingConfigs.fixed', s)

if n1 != 1 or n2 < 1:
    sys.exit(f"Could not patch signing config in {path} ({n1}, {n2})")
open(path, "w").write(s)
print(f"Patched {path}")

# ---- Notifications (flutter_local_notifications) ----
# Core library desugaring + minimum Android 7 (API 24).
s = open(path).read()
if path.endswith(".kts"):
    s, n = re.subn(r'compileOptions\s*\{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', s, count=1)
    if n != 1:
        sys.exit("Could not enable desugaring")
    s, _ = re.subn(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = maxOf(24, flutter.minSdkVersion)', s)
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
else:
    s, n = re.subn(r'compileOptions\s*\{', 'compileOptions {\n        coreLibraryDesugaringEnabled true', s, count=1)
    if n != 1:
        sys.exit("Could not enable desugaring")
    s, _ = re.subn(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion Math.max(24, flutter.minSdkVersion)', s)
    s += '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n'
open(path, "w").write(s)

# Manifest: permissions and the receivers that deliver scheduled reminders
# (also after a reboot or an app update).
manifest = "build_app/android/app/src/main/AndroidManifest.xml"
m = open(manifest).read()
perms = (
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
)
m = m.replace("<application", perms + "    <application", 1)
receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>'''
if "</application>" not in m:
    sys.exit("No </application> in manifest")
m = m.replace("</application>", receivers.lstrip("\n"), 1)
open(manifest, "w").write(m)
print("Patched notifications setup")
