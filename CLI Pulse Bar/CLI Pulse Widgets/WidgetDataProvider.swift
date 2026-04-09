import Foundation
import WidgetKit

// MARK: - Shared Data

struct WidgetData: Codable {
    let totalUsageToday: Int
    let totalCostToday: Double
    let activeSessions: Int
    let unresolvedAlerts: Int
    let providers: [WidgetProviderData]
    let lastUpdated: Date

    static let empty = WidgetData(
        totalUsageToday: 0,
        totalCostToday: 0,
        activeSessions: 0,
        unresolvedAlerts: 0,
        providers: [],
        lastUpdated: Date()
    )

    static let preview = WidgetData(
        totalUsageToday: 245_000,
        totalCostToday: 3.45,
        activeSessions: 3,
        unresolvedAlerts: 1,
        providers: [
            WidgetProviderData(name: "Claude", usage: 120_000, quota: 500_000, costToday: 1.85, iconName: "brain.head.profile"),
            WidgetProviderData(name: "Codex", usage: 85_000, quota: 200_000, costToday: 1.20, iconName: "chevron.left.forwardslash.chevron.right"),
            WidgetProviderData(name: "Gemini", usage: 40_000, quota: 300_000, costToday: 0.40, iconName: "sparkles"),
        ],
        lastUpdated: Date()
    )
}

struct WidgetProviderData: Codable, Identifiable {
    let name: String
    let usage: Int
    let quota: Int?
    let costToday: Double
    let iconName: String

    var id: String { name }

    var usagePercent: Double {
        guard let quota = quota, quota > 0 else { return 0 }
        return Double(usage) / Double(quota)
    }

    var formattedUsage: String {
        if usage >= 1_000_000 {
            return String(format: "%.1fM", Double(usage) / 1_000_000)
        } else if usage >= 1_000 {
            return String(format: "%.0fK", Double(usage) / 1_000)
        }
        return "\(usage)"
    }

    var formattedCost: String {
        if costToday < 0.01 { return "$0.00" }
        return String(format: "$%.2f", costToday)
    }
}

// MARK: - App Group Storage

enum WidgetStorage {
    static let suiteName = "group.yyh.CLI-Pulse"
    static let dataKey = "widgetData"

    static func save(_ data: WidgetData) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: dataKey)
        }
    }

    static func load() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: dataKey),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return .empty
        }
        return decoded
    }
}

// MARK: - Timeline Provider

struct CLIPulseTimelineProvider: TimelineProvider {
    typealias Entry = CLIPulseEntry

    func placeholder(in context: Context) -> CLIPulseEntry {
        CLIPulseEntry(date: Date(), data: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CLIPulseEntry) -> Void) {
        if context.isPreview {
            completion(CLIPulseEntry(date: Date(), data: .preview))
        } else {
            completion(CLIPulseEntry(date: Date(), data: WidgetStorage.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CLIPulseEntry>) -> Void) {
        let data = WidgetStorage.load()
        let entry = CLIPulseEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct CLIPulseEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Single Provider Timeline Provider

struct SingleProviderTimelineProvider: TimelineProvider {
    typealias Entry = SingleProviderEntry

    private static let fallbackProvider = WidgetProviderData(
        name: "Claude", usage: 0, quota: 100, costToday: 0, iconName: "brain.head.profile"
    )

    private static var previewProvider: WidgetProviderData {
        WidgetData.preview.providers.first ?? fallbackProvider
    }

    func placeholder(in context: Context) -> SingleProviderEntry {
        SingleProviderEntry(date: Date(), provider: Self.previewProvider)
    }

    func getSnapshot(in context: Context, completion: @escaping (SingleProviderEntry) -> Void) {
        if context.isPreview {
            completion(SingleProviderEntry(date: Date(), provider: Self.previewProvider))
        } else {
            let data = WidgetStorage.load()
            let provider = data.providers.first ?? Self.previewProvider
            completion(SingleProviderEntry(date: Date(), provider: provider))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SingleProviderEntry>) -> Void) {
        let data = WidgetStorage.load()
        let provider = data.providers.first ?? Self.previewProvider
        let entry = SingleProviderEntry(date: Date(), provider: provider)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SingleProviderEntry: TimelineEntry {
    let date: Date
    let provider: WidgetProviderData
}
