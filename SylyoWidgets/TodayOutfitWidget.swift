import WidgetKit
import SwiftUI

struct TodayOutfitEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayOutfitSnapshot
}

struct TodayOutfitProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayOutfitEntry {
        TodayOutfitEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayOutfitEntry) -> Void) {
        let snapshot = TodayOutfitSnapshot.load() ?? .placeholder
        completion(TodayOutfitEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayOutfitEntry>) -> Void) {
        let snapshot = TodayOutfitSnapshot.load() ?? .placeholder
        let entry = TodayOutfitEntry(date: Date(), snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TodayOutfitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodayOutfitEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                Color.clear
                LinearGradient(
                    colors: [
                        WidgetBrand.sky.opacity(0.30),
                        WidgetBrand.powder.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            Text(entry.snapshot.outfitName)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(entry.snapshot.temperatureText ?? entry.snapshot.occasion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .widgetAccentable()
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(entry.snapshot.occasion, systemImage: "tshirt.fill")
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                Text(entry.snapshot.outfitName)
                    .font(.title3.bold())
                    .lineLimit(2)
                Text(entry.snapshot.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemLarge ? 4 : 2)
                Spacer(minLength: 0)
                HStack {
                    if let temp = entry.snapshot.temperatureText {
                        Text(temp).font(.caption.weight(.semibold))
                    }
                    Text("\(Int(entry.snapshot.confidence * 100))% match")
                        .font(.caption)
                        .widgetAccentable()
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .widgetAccentable()
                Text("Sylyo")
                    .font(.title2.bold())
                Spacer()
                Text(entry.snapshot.temperatureText ?? "—")
                    .font(.title3.weight(.semibold))
                    .widgetAccentable()
            }

            Text(entry.snapshot.outfitName)
                .font(.largeTitle.bold())
                .lineLimit(3)

            Text(entry.snapshot.occasion)
                .font(.headline)
                .widgetAccentable()

            Text(entry.snapshot.rationale)
                .font(.body)
                .foregroundStyle(.secondary)

            if let weather = entry.snapshot.weatherSummary {
                Label(weather, systemImage: "cloud.sun.fill")
                    .font(.subheadline)
                    .widgetAccentable()
            }

            Spacer(minLength: 0)

            HStack {
                Text("\(Int(entry.snapshot.confidence * 100))% confidence")
                    .font(.headline)
                Spacer()
                Text("\(entry.snapshot.wardrobeCount) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TodayOutfitWidget: Widget {
    let kind = "TodayOutfitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayOutfitProvider()) { entry in
            TodayOutfitWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Outfit")
        .description("AI outfit recommendation with weather context.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
