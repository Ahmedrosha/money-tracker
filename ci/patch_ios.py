"""Prepares the generated iOS project for App Store / TestFlight builds:
bundle id, automatic signing with the team, app name, Info.plist keys and
notification delegate."""
import os
import plistlib
import re
import sys

BUNDLE_ID = "com.rashad.moneytracker"
team = os.environ.get("APPLE_TEAM_ID", "").strip()
if not team:
    sys.exit("APPLE_TEAM_ID is not set")

ios = "build_ios/ios"

# --- Xcode project: bundle id + automatic signing on the app target only.
pbx = os.path.join(ios, "Runner.xcodeproj/project.pbxproj")
s = open(pbx).read()


def app_target(m):
    return (f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};\n"
            f"\t\t\t\tDEVELOPMENT_TEAM = {team};\n"
            f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")


s, n = re.subn(r"PRODUCT_BUNDLE_IDENTIFIER = (?![^;]*RunnerTests)[^;]*;", app_target, s)
s = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = [^;]*\.RunnerTests;",
           f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.RunnerTests;", s)
print(f"bundle id set in {n} build configurations")
if n == 0:
    sys.exit("could not find the app bundle id in project.pbxproj")
open(pbx, "w").write(s)

# --- Info.plist
plist_path = os.path.join(ios, "Runner/Info.plist")
with open(plist_path, "rb") as f:
    p = plistlib.load(f)
p["CFBundleDisplayName"] = "Expense & Wealth Tracker"
p["CFBundleName"] = "Money Tracker"
# Only standard HTTPS is used, so no export compliance paperwork.
p["ITSAppUsesNonExemptEncryption"] = False
# Backups can be seen in the Files app.
p["UIFileSharingEnabled"] = True
p["LSSupportsOpeningDocumentsInPlace"] = True
# The file picker library links these frameworks; Apple requires the texts
# even though the app only picks backup files.
p.setdefault("NSPhotoLibraryUsageDescription",
             "Only used if you choose a file from your photo library.")
p.setdefault("NSCameraUsageDescription",
             "Only used if you choose to take a photo to attach.")
p.setdefault("NSMicrophoneUsageDescription",
             "Not used by Expense & Wealth Tracker.")
p["NSFaceIDUsageDescription"] = "Face ID unlocks Expense & Wealth Tracker."
p.setdefault("NSLocationWhenInUseUsageDescription",
             "Not used by Expense & Wealth Tracker.")
p.setdefault("NSAppleMusicUsageDescription",
             "Not used by Expense & Wealth Tracker.")
with open(plist_path, "wb") as f:
    plistlib.dump(p, f)

# --- Show notifications while the app is open.
delegate = os.path.join(ios, "Runner/AppDelegate.swift")
d = open(delegate).read()
if "UNUserNotificationCenter" not in d:
    if "import UserNotifications" not in d:
        d = d.replace("import UIKit", "import UIKit\nimport UserNotifications", 1)
    d, k = re.subn(
        r"(\n(\s*)GeneratedPluginRegistrant\.register\([^\n]*\n)",
        r"\1\2UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate\n",
        d, count=1)
    print("notification delegate added" if k else "notification delegate: pattern not found, skipped")
    open(delegate, "w").write(d)
print(open(delegate).read())
