import WidgetKit
import SwiftUI

struct WardrobeGlanceEntry: TimelineEntry {
    let date: Date
    let count: Int
    let outfitName: String
}

struct WardrobeGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> WardrobeGlanceEntry {
        WardrobeGlanceEntry(date: Date(), count: 24, outfitName: "Capsule ready")
    }

    func getSnapshot(in context: Context, completion: @escaping (WardrobeGlanceEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WardrobeGlanceEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> WardrobeGlanceEntry {
        let snapshot = TodayOutfitSnapshot.load()
        return WardrobeGlanceEntry(
            date: Date(),
            count: snapshot?.wardrobeCount ?? 0,
            outfitName: snapshot?.outfitName ?? "Open Sylyo to sync"
        )
    }
}

struct WardrobeGlanceWidgetView: View {
    var entry: WardrobeGlanceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Wardrobe", systemImage: "tshirt.fill")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            Text("\(entry.count)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .widgetAccentable()
            Text("pieces ready")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(entry.outfitName)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .containerBackground(for: .widget) {
            ZStack {
                Color.clear
                LinearGradient(
                    colors: [WidgetBrand.sky.opacity(0.28), WidgetBrand.powder.opacity(0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

struct WardrobeGlanceWidget: Widget {
    let kind = "WardrobeGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WardrobeGlanceProvider()) { entry in
            WardrobeGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Wardrobe Glance")
        .description("See how many pieces are in your digital closet.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
