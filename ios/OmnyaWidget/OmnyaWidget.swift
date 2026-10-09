import ActivityKit
import SwiftUI
import WidgetKit

// Brand colours, matching lib/core/theme/omnya_colors.dart.
extension Color {
  static let plum = Color(red: 0x4A / 255, green: 0x1E / 255, blue: 0x35 / 255)
  static let cream = Color(red: 0xFD / 255, green: 0xFB / 255, blue: 0xF7 / 255)
  static let sand = Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xEA / 255)
  static let charcoal = Color(red: 0x1F / 255, green: 0x1D / 255, blue: 0x1C / 255)
  static let muted = Color(red: 0x6E / 255, green: 0x67 / 255, blue: 0x63 / 255)
}

/// What the app writes to the shared app group whenever her data changes.
struct WidgetData: Codable {
  var next: String?       // "Reta, 2 mg"
  var when: String?       // "Tomorrow 9 am · left thigh"
  var day: Int?           // days on protocol
  var runout: String?     // "Vial runs out Thu"
}

struct Entry: TimelineEntry {
  let date: Date
  let data: WidgetData
}

struct Provider: TimelineProvider {
  static func load() -> WidgetData {
    guard let json = UserDefaults(suiteName: "group.com.omnya.omnya")?.string(forKey: "widget"),
      let data = json.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(WidgetData.self, from: data)
    else { return WidgetData() }
    return decoded
  }

  func placeholder(in context: Context) -> Entry {
    Entry(date: .now, data: WidgetData(next: "Reta, 2 mg", when: "Tomorrow 9 am · left thigh", day: 41, runout: "Vial runs out Thu"))
  }
  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : Entry(date: .now, data: Self.load()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    // The app reloads the widget on every change; midnight refresh keeps "today" honest.
    let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400)
    completion(Timeline(entries: [Entry(date: .now, data: Self.load())], policy: .after(midnight)))
  }
}

struct NextDoseView: View {
  @Environment(\.widgetFamily) var family
  let entry: Entry

  var body: some View {
    let d = entry.data
    switch family {
    case .accessoryInline:
      Text(d.next.map { "\($0) · \(d.when ?? "")" } ?? "Omnya")
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Text(d.next ?? "Add your stack").font(.headline).widgetAccentable()
        if let when = d.when { Text(when).font(.caption) }
        if let day = d.day { Text("Day \(day)").font(.caption2) }
      }
    default:
      VStack(alignment: .leading, spacing: 4) {
        Text("Next dose").font(.caption).foregroundStyle(Color.muted)
        Text(d.next ?? "Nothing to log yet").font(.system(.title3, design: .serif)).foregroundStyle(Color.charcoal)
          .minimumScaleFactor(0.7).lineLimit(2)
        if let when = d.when { Text(when).font(.caption).foregroundStyle(Color.charcoal) }
        Spacer(minLength: 0)
        HStack {
          if let day = d.day { Text("Day \(day)").font(.caption2.weight(.semibold)).foregroundStyle(Color.plum) }
          Spacer()
          if let runout = d.runout { Text(runout).font(.caption2).foregroundStyle(Color.muted) }
        }
      }
    }
  }
}

struct NextDoseWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NextDose", provider: Provider()) { entry in
      NextDoseView(entry: entry).containerBackground(Color.sand, for: .widget)
    }
    .configurationDisplayName("Next dose")
    .description("Your next dose, days on protocol and runout.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
  }
}

struct ShotDayLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ShotDayAttributes.self) { context in
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("SHOT DAY").font(.caption2.weight(.bold)).foregroundStyle(Color.cream.opacity(0.7))
          Text("\(context.state.compound)'s ready when you are").font(.headline).foregroundStyle(Color.cream)
          Text(([context.state.dose, context.state.site].filter { !$0.isEmpty }).joined(separator: " · "))
            .font(.caption).foregroundStyle(Color.cream.opacity(0.8))
        }
        Spacer()
        Text("Tap to log").font(.caption.weight(.semibold)).foregroundStyle(Color.plum)
          .padding(.horizontal, 10).padding(.vertical, 6).background(Color.cream, in: Capsule())
      }
      .padding(16)
      .activityBackgroundTint(Color.plum)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Text(context.state.compound).font(.headline) }
        DynamicIslandExpandedRegion(.trailing) { Text(context.state.dose) }
        DynamicIslandExpandedRegion(.bottom) { Text(context.state.site.isEmpty ? "Tap to log" : "\(context.state.site) · tap to log") }
      } compactLeading: {
        Text("Shot").font(.caption2.weight(.bold))
      } compactTrailing: {
        Text(context.state.dose).font(.caption2)
      } minimal: {
        Image(systemName: "drop.fill")
      }
    }
  }
}

@main
struct OmnyaWidgets: WidgetBundle {
  var body: some Widget {
    NextDoseWidget()
    ShotDayLiveActivity()
  }
}
