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
