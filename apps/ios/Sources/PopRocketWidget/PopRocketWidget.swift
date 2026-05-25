import PopRocketIntents
import PopRocketKit
import SwiftUI
import WidgetKit

public struct PopRocketWidget: Widget {
    public let kind = "PopRocketWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("PopRocket")
        .description("Homelab status and actions")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), cards: [], stale: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = loadEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func loadEntry() -> Entry {
        let cached = try? AppGroupCache().loadCards()
        return Entry(date: Date(), cards: cached?.cards ?? [], stale: cached?.isStale ?? true)
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let cards: [CardSnapshot]
    let stale: Bool
}

struct WidgetView: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PopRocket")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(entry.stale ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
            }
            if let card = entry.cards.first {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(card.value?.displayText ?? card.status)
                    .font(.title3.weight(.medium))
                    .lineLimit(2)
                Text(entry.stale ? "Stale" : "Fresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(intent: RunActionIntent(actionID: "ack", eventID: nil)) {
                    Label("Ack", systemImage: "checkmark")
                }
            } else {
                Spacer()
                Text("No cached cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .containerBackground(.background, for: .widget)
    }
}
