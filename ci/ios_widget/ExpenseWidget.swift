import SwiftUI
import WidgetKit

// Home screen and lock screen widgets. The app saves ready-made text into
// the shared App Group (home_widget); the widgets only show it.

private let appGroup = "group.com.rashad.moneytracker"
private let teal = Color(red: 0.0, green: 0.537, blue: 0.482)
private let tealDark = Color(red: 0.0, green: 0.37, blue: 0.33)
private let surface = Color(red: 0.11, green: 0.153, blue: 0.149)
private let accent = Color(red: 0.298, green: 0.765, blue: 0.698)
private let muted = Color(red: 0.62, green: 0.69, blue: 0.68)
private let red = Color(red: 0.937, green: 0.416, blue: 0.416)
private let green = Color(red: 0.373, green: 0.812, blue: 0.541)
private let amber = Color(red: 0.94, green: 0.71, blue: 0.29)

struct Snap: TimelineEntry {
  let date: Date
  let d: [String: String]
  func s(_ k: String, _ def: String = "") -> String {
    let v = d[k] ?? ""
    return v.isEmpty ? def : v
  }
  var rtl: Bool { d["rtl"] == "1" }
}

private let keys = ["hidden", "unit", "updated", "l_add", "l_networth", "l_month", "l_spent",
                    "l_income", "l_due", "networth", "networth_short", "spent", "spent_short",
                    "income", "budget", "budget_pct", "due_title", "due_sub", "recurring", "rtl"]

private func load() -> [String: String] {
  let u = UserDefaults(suiteName: appGroup)
  var out = [String: String]()
  for k in keys { out[k] = u?.string(forKey: k) ?? "" }
  return out
}

private let sample: [String: String] = [
  "unit": "EGP", "updated": "Updated 09:41", "l_add": "Add Expense", "l_networth": "Net Worth",
  "l_month": "This Month", "l_spent": "Spent", "l_income": "Income", "l_due": "Due Soon",
  "networth": "2,504,750.00", "networth_short": "2.50M", "spent": "18,240.50", "spent_short": "18.2K",
  "income": "42,000.00", "budget": "18,240.50 of 25,000.00 · 73%", "budget_pct": "73",
  "due_title": "CIB · Visa Gold", "due_sub": "12,400.00 EGP · due 15 Oct",
  "recurring": "2 recurring items to confirm",
]

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> Snap { Snap(date: Date(), d: sample) }
  func getSnapshot(in context: Context, completion: @escaping (Snap) -> Void) {
    let d = load()
    completion(Snap(date: Date(), d: context.isPreview || (d["unit"] ?? "").isEmpty ? sample : d))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<Snap>) -> Void) {
    let e = Snap(date: Date(), d: load())
    completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(1800))))
  }
}

extension View {
  @ViewBuilder func widgetBG<B: View>(@ViewBuilder _ bg: () -> B) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.containerBackground(for: .widget) { bg() }
    } else {
      self.background(bg())
    }
  }
}

// MARK: Add Expense

struct AddView: View {
  @Environment(\.widgetFamily) var family
  let e: Snap
  var body: some View {
    switch family {
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "plus").font(.system(size: 22, weight: .bold))
      }
      .widgetBG { Color.clear }
    default:
      VStack(spacing: 6) {
        Image(systemName: "plus.circle.fill").font(.system(size: 46)).foregroundColor(.white)
        Text(e.s("l_add", "Add Expense")).font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .widgetBG { LinearGradient(colors: [teal, tealDark], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }
  }
}

struct AddExpenseWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "AddExpenseWidget", provider: Provider()) { e in
      AddView(e: e).widgetURL(URL(string: "ewtracker://add?type=expense"))
    }
    .configurationDisplayName("Add Expense")
    .description("Add an expense in one tap.")
    .supportedFamilies([.systemSmall, .accessoryCircular])
  }
}

struct VoiceView: View {
  @Environment(\.widgetFamily) var family
  let e: Snap
  var body: some View {
    switch family {
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "mic.fill").font(.system(size: 20, weight: .bold))
      }
      .widgetBG { Color.clear }
    default:
      VStack(spacing: 6) {
        Image(systemName: "mic.circle.fill").font(.system(size: 46)).foregroundColor(.white)
        Text(e.s("l_voice", "Say an Expense")).font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .widgetBG { LinearGradient(colors: [teal, tealDark], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }
  }
}

struct VoiceExpenseWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "VoiceExpenseWidget", provider: Provider()) { e in
      VoiceView(e: e).widgetURL(URL(string: "ewtracker://add?type=expense&voice=1"))
    }
    .configurationDisplayName("Say an Expense")
    .description("Add an expense by voice.")
    .supportedFamilies([.systemSmall, .accessoryCircular])
  }
}

// MARK: Net Worth

struct NetWorthView: View {
  @Environment(\.widgetFamily) var family
  let e: Snap
  var body: some View {
    switch family {
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text(e.s("l_networth", "Net Worth")).font(.system(size: 12, weight: .semibold))
        Text(e.s("networth", "—")).font(.system(size: 17, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
        Text(e.s("unit")).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .widgetBG { Color.clear }
    case .accessoryInline:
      Text("\(e.s("l_networth", "Net Worth")) \(e.s("networth_short", "—"))")
        .widgetBG { Color.clear }
    default:
      VStack(alignment: .leading, spacing: 2) {
        Text(e.s("l_networth", "Net Worth")).font(.system(size: 13, weight: .semibold)).foregroundColor(accent)
        Spacer()
        Text(e.s("networth_short", "—")).font(.system(size: 30, weight: .bold)).foregroundColor(.white)
          .lineLimit(1).minimumScaleFactor(0.5)
        Text(e.s("unit")).font(.system(size: 13)).foregroundColor(muted)
        Text(e.s("updated", "Open the app")).font(.system(size: 10)).foregroundColor(muted.opacity(0.8)).padding(.top, 4)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .widgetBG { surface }
    }
  }
}

struct NetWorthWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NetWorthWidget", provider: Provider()) { e in
      NetWorthView(e: e).widgetURL(URL(string: "ewtracker://open?to=accounts"))
    }
    .configurationDisplayName("Net Worth")
    .description("Your net worth.")
    .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
  }
}

// MARK: This Month

struct MonthView: View {
  @Environment(\.widgetFamily) var family
  let e: Snap
  var pct: Int { Int(e.s("budget_pct", "-1")) ?? -1 }
  var body: some View {
    switch family {
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text("\(e.s("l_spent", "Spent")) · \(e.s("l_month", "This Month"))").font(.system(size: 12, weight: .semibold))
        Text(e.s("spent", "—")).font(.system(size: 17, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
        if pct >= 0 {
          ProgressView(value: Double(min(pct, 100)), total: 100).tint(.primary)
        } else {
          Text(e.s("unit")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .widgetBG { Color.clear }
    case .accessoryInline:
      Text("\(e.s("l_spent", "Spent")) \(e.s("spent_short", "—"))")
        .widgetBG { Color.clear }
    default:
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(e.s("l_month", "This Month")).font(.system(size: 13, weight: .semibold)).foregroundColor(accent)
          Spacer()
          Link(destination: URL(string: "ewtracker://add?type=expense")!) {
            Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundColor(accent)
          }
        }
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 2) {
            Text(e.s("l_spent", "Spent")).font(.system(size: 11)).foregroundColor(muted)
            Text(e.s("spent", "—")).font(.system(size: 19, weight: .bold)).foregroundColor(red)
              .lineLimit(1).minimumScaleFactor(0.6)
          }
          Spacer()
          VStack(alignment: .leading, spacing: 2) {
            Text(e.s("l_income", "Income")).font(.system(size: 11)).foregroundColor(muted)
            Text(e.s("income", "—")).font(.system(size: 19, weight: .bold)).foregroundColor(green)
              .lineLimit(1).minimumScaleFactor(0.6)
          }
        }
        if pct >= 0 {
          ProgressView(value: Double(min(pct, 100)), total: 100)
            .tint(pct >= 100 ? red : (pct >= 80 ? amber : accent))
          Text(e.s("budget")).font(.system(size: 10)).foregroundColor(muted).lineLimit(1)
        } else {
          Text(e.s("updated")).font(.system(size: 10)).foregroundColor(muted)
        }
      }
      .widgetBG { surface }
    }
  }
}

struct MonthWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MonthWidget", provider: Provider()) { e in
      MonthView(e: e).widgetURL(URL(string: "ewtracker://open?to=transactions"))
    }
    .configurationDisplayName("This Month")
    .description("Spending, income and budget this month.")
    .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryInline])
  }
}

// MARK: Due Soon

struct DueView: View {
  let e: Snap
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(e.s("l_due", "Due Soon")).font(.system(size: 13, weight: .semibold)).foregroundColor(accent)
      Spacer()
      HStack(spacing: 10) {
        Image(systemName: "creditcard.fill").font(.system(size: 22)).foregroundColor(amber)
        VStack(alignment: .leading, spacing: 2) {
          Text(e.s("due_title", "—")).font(.system(size: 16, weight: .semibold)).foregroundColor(.white).lineLimit(1)
          Text(e.s("due_sub")).font(.system(size: 13)).foregroundColor(amber).lineLimit(1)
        }
      }
      if !e.s("recurring").isEmpty {
        HStack(spacing: 6) {
          Image(systemName: "bell.badge.fill").font(.system(size: 12)).foregroundColor(red)
          Text(e.s("recurring")).font(.system(size: 12)).foregroundColor(muted).lineLimit(1)
        }
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .widgetBG { surface }
  }
}

struct DueWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "DueWidget", provider: Provider()) { e in
      DueView(e: e).widgetURL(URL(string: "ewtracker://open?to=due"))
    }
    .configurationDisplayName("Due Soon")
    .description("Next card payment and recurring items to confirm.")
    .supportedFamilies([.systemMedium])
  }
}

@main
struct ExpenseWidgets: WidgetBundle {
  var body: some Widget {
    AddExpenseWidget()
    VoiceExpenseWidget()
    NetWorthWidget()
    MonthWidget()
    DueWidget()
  }
}
