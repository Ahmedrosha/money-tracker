"""Makes release builds always use ci/debug.keystore, so every APK is signed
with the same key and installs over the previous version."""
import os
import re
import sys

app = "build_app/android/app"
keystore = os.path.abspath("ci/debug.keystore")
# Play Store upload key (Google re-signs with its own key for users).
upload_ks = os.path.abspath("ci/upload.keystore")
upload_pw = open("ci/upload.password").read().strip()
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
        create("upload") {{
            storeFile = file("{upload_ks}")
            storePassword = "{upload_pw}"
            keyAlias = "upload"
            keyPassword = "{upload_pw}"
        }}
    }}
'''
    s, n1 = re.subn(r'(\n\s*buildTypes\s*\{)', block + r'\1', s, count=1)
    # PLAY_UPLOAD=1 -> Play Store bundle; otherwise the sideload APK key.
    s, n2 = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                    'signingConfig = if (System.getenv("PLAY_UPLOAD") == "1") '
                    'signingConfigs.getByName("upload") else signingConfigs.getByName("fixed")', s)
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
        upload {{
            storeFile file("{upload_ks}")
            storePassword "{upload_pw}"
            keyAlias "upload"
            keyPassword "{upload_pw}"
        }}
    }}
'''
    s, n1 = re.subn(r'(\n\s*buildTypes\s*\{)', block + r'\1', s, count=1)
    s, n2 = re.subn(r'signingConfig\s+signingConfigs\.debug',
                    'signingConfig System.getenv("PLAY_UPLOAD") == "1" ? '
                    'signingConfigs.upload : signingConfigs.fixed', s)

if n1 != 1 or n2 < 1:
    sys.exit(f"Could not patch signing config in {path} ({n1}, {n2})")
# Same app ID as the Play Store listing and the iPhone app.
s, n3 = re.subn(r'applicationId\s*=?\s*"com\.rashad\.money_tracker"',
                lambda m: m.group(0).replace("money_tracker", "moneytracker"), s)
if n3 != 1:
    sys.exit("Could not set applicationId")
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

# ---- App lock (local_auth) ----
# Needs a FragmentActivity, the biometric permission and AppCompat themes.
import glob
acts = glob.glob("build_app/android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not acts:
    sys.exit("MainActivity.kt not found")
for act in acts:
    a = open(act).read()
    a = a.replace("io.flutter.embedding.android.FlutterActivity",
                  "io.flutter.embedding.android.FlutterFragmentActivity")
    a = re.sub(r":\s*FlutterActivity\(\)", ": FlutterFragmentActivity()", a)
    open(act, "w").write(a)
    print(a)

m = open(manifest).read()
m = m.replace("<application",
              '<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application', 1)
open(manifest, "w").write(m)

s = open(path).read()
if path.endswith(".kts"):
    s += '\ndependencies {\n    implementation("androidx.appcompat:appcompat:1.7.0")\n}\n'
else:
    s += '\ndependencies {\n    implementation "androidx.appcompat:appcompat:1.7.0"\n}\n'
open(path, "w").write(s)

for styles in glob.glob("build_app/android/app/src/main/res/values*/styles.xml"):
    x = open(styles).read()
    x = x.replace("@android:style/Theme.Light.NoTitleBar", "Theme.AppCompat.Light.NoActionBar")
    x = x.replace("@android:style/Theme.Black.NoTitleBar", "Theme.AppCompat.NoActionBar")
    open(styles, "w").write(x)
    print("Patched", styles)
print("Patched app lock setup")

# ---- Bank SMS (Android) ----
# MainActivity gets a channel that reads the SMS inbox. The READ_SMS
# permission itself is only added for the GitHub APK (see build.yml); the
# Play bundle leaves it out, and the app then hides automatic reading.
SMS_ACTIVITY = '''
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ewt/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(declared())
                    "granted" -> result.success(granted())
                    "request" -> {
                        if (!declared()) {
                            result.success(false)
                        } else if (granted()) {
                            result.success(true)
                        } else {
                            pending?.success(false)
                            pending = result
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.READ_SMS), 7701)
                        }
                    }
                    "inbox" -> {
                        val out = ArrayList<Map<String, Any>>()
                        if (granted()) {
                            val since = (call.argument<Number>("since") ?: 0).toLong()
                            try {
                                contentResolver.query(
                                    Uri.parse("content://sms/inbox"),
                                    arrayOf("address", "body", "date"),
                                    "date > ?", arrayOf(since.toString()), "date ASC"
                                )?.use { c ->
                                    while (c.moveToNext() && out.size < 500) {
                                        out.add(mapOf(
                                            "address" to (c.getString(0) ?: ""),
                                            "body" to (c.getString(1) ?: ""),
                                            "date" to c.getLong(2)))
                                    }
                                }
                            } catch (e: Exception) {
                            }
                        }
                        result.success(out)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun declared(): Boolean = try {
        packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions?.contains(Manifest.permission.READ_SMS) == true
    } catch (e: Exception) {
        false
    }

    private fun granted(): Boolean = declared() &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) ==
        PackageManager.PERMISSION_GRANTED

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7701) {
            pending?.success(granted())
            pending = null
        }
    }
}
'''
for act in acts:
    a = open(act).read()
    pkg = re.search(r'^package\s+\S+', a, re.M)
    if not pkg:
        sys.exit("No package line in MainActivity.kt")
    open(act, "w").write(pkg.group(0) + "\n" + SMS_ACTIVITY)
    print("Wrote SMS channel into", act)
