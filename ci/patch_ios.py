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
# Text recognition (receipts) needs iOS 15.5 or later.
s = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.5;", s)
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
p["NSPhotoLibraryUsageDescription"] = "Choose a receipt photo to attach to a transaction."
p["NSCameraUsageDescription"] = "Take a photo of a receipt to fill in a transaction."
p["NSMicrophoneUsageDescription"] = "Say a transaction, e.g. \"Spent 450 on fuel\", to fill it in."
p["NSSpeechRecognitionUsageDescription"] = "Turns what you say into a transaction to check and save."
p["NSFaceIDUsageDescription"] = "Face ID unlocks Expense & Wealth Tracker."
p.setdefault("NSLocationWhenInUseUsageDescription",
             "Not used by Expense & Wealth Tracker.")
p.setdefault("NSAppleMusicUsageDescription",
             "Not used by Expense & Wealth Tracker.")
# Bank messages sent in by a Shortcuts automation: ewtracker://sms?text=…
p["CFBundleURLTypes"] = [{
    "CFBundleURLName": "com.rashad.moneytracker.sms",
    "CFBundleURLSchemes": ["ewtracker"],
}]
# Links are handled by the app (app_links), not Flutter's router.
p["FlutterDeepLinkingEnabled"] = False
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

# --- "Add Bank Message" action for Shortcuts (iOS 16+). It runs without
# opening the app and appends the SMS to Documents/incoming_sms.jsonl,
# which the app reads into Bank Messages when it next opens.
d = open(delegate).read()
if "AddBankMessageIntent" not in d:
    if "import AppIntents" not in d:
        d = d.replace("import UIKit", "import UIKit\nimport AppIntents", 1)
    if "import UserNotifications" not in d:
        d = d.replace("import UIKit", "import UIKit\nimport UserNotifications", 1)
    d += '''

@available(iOS 16.0, *)
struct AddBankMessageIntent: AppIntent {
  static var title: LocalizedStringResource = "Add Bank Message"
  static var description = IntentDescription(
    "Adds a bank SMS to Bank Messages in Expense & Wealth Tracker, to confirm later.")
  static var openAppWhenRun: Bool = false

  @Parameter(title: "Message")
  var message: String

  @Parameter(title: "Sender")
  var sender: String?

  func perform() async throws -> some IntentResult {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let file = dir.appendingPathComponent("incoming_sms.jsonl")
    let entry: [String: Any] = [
      "from": sender ?? "",
      "text": message,
      "at": Int(Date().timeIntervalSince1970 * 1000),
    ]
    var line = try JSONSerialization.data(withJSONObject: entry)
    line.append(0x0A)
    if FileManager.default.fileExists(atPath: file.path) {
      let h = try FileHandle(forWritingTo: file)
      _ = try h.seekToEnd()
      try h.write(contentsOf: line)
      try h.close()
    } else {
      try line.write(to: file)
    }
    await Self.notify(message)
    return .result()
  }

  /// A short notification ("6,030.00 EGP at MY FAWRY · tap to review"),
  /// shown only when notifications are allowed for the app.
  static func notify(_ raw: String) async {
    let text = raw.replacingOccurrences(of: "\\\\s+", with: " ", options: .regularExpression)
    let lower = text.lowercased()
    for w in ["otp", "one-time", "password", "passcode", "verification", "code is",
              "declined", "rejected", "unsuccessful", "failed", "رمز", "مرفوض"] {
      if lower.contains(w) { return }
    }
    let cur = "(EGP|USD|EUR|GBP|SAR|AED|KWD|QAR|LE|L\\\\.E\\\\.?|جم|جنيه|ج\\\\.م)"
    let num = "([0-9][0-9 ,]*(?:\\\\.[0-9]+)?)"
    func first(_ pattern: String) -> [String]? {
      guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
      return (0..<m.numberOfRanges).map { i in
        guard let r = Range(m.range(at: i), in: text) else { return "" }
        return String(text[r])
      }
    }
    var amount = ""
    if let a = first(cur + "\\\\s*" + num) { amount = a[2].trimmingCharacters(in: .whitespaces) + " " + a[1] }
    else if let a = first(num + "\\\\s*" + cur) { amount = a[1].trimmingCharacters(in: .whitespaces) + " " + a[2] }
    if amount.isEmpty { return }
    let arabic = UserDefaults(suiteName: "group.com.rashad.moneytracker")?.string(forKey: "rtl") == "1"
    let statement = lower.contains("statement") || text.contains("كشف حساب")
    var where_ = ""
    if !statement, let m = first("\\\\s(?:at|@)\\\\s+(.+?)(?=\\\\s+on\\\\s|\\\\.\\\\s|,|\\\\s+and\\\\s|\\\\s+Available|$)") {
      where_ = m[1]
    }
    let content = UNMutableNotificationContent()
    if statement {
      content.title = arabic ? "كشف حساب البطاقة" : "Card statement"
      content.body = amount + (arabic ? " · اضغط للمراجعة" : " · tap to compare with the app")
    } else {
      content.title = arabic ? "رسالة بنك جديدة" : "New bank message"
      content.body = amount + (where_.isEmpty ? "" : (arabic ? " لدى " : " at ") + where_)
        + (arabic ? " · اضغط للمراجعة" : " · tap to review")
    }
    content.sound = nil
    content.userInfo = ["ewt": "sms"]
    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    try? await UNUserNotificationCenter.current().add(req)
  }
}
'''
    open(delegate, "w").write(d)
    print("Added the Add Bank Message action")
