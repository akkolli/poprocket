import AppIntents
import PopRocketIntents
import PopRocketKit
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

@main
public struct PopRocketWidgets: WidgetBundle {
    public init() {}

    public var body: some Widget {
        PopRocketStatusWidget()
        PopRocketHealthWidget()
        PopRocketActionsWidget()
        PopRocketAccessoryWidget()
    }
}

private struct PopRocketStatusWidget: Widget {
    let kind = "PopRocketStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardWidgetProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("PopRocket Status")
        .description("Shows cached active bridge health at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

private struct PopRocketHealthWidget: Widget {
    let kind = "PopRocketHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardWidgetProvider()) { entry in
            HealthWidgetView(entry: entry)
        }
        .configurationDisplayName("PopRocket Health")
        .description("Shows cached monitored service state and freshness.")
        .supportedFamilies([.systemMedium])
    }
}

private struct PopRocketActionsWidget: Widget {
    let kind = "PopRocketActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardWidgetProvider()) { entry in
            ActionsWidgetView(entry: entry)
        }
        .configurationDisplayName("PopRocket Actions")
        .description("Runs explicitly trusted saved actions and shows cached action freshness.")
        .supportedFamilies([.systemMedium])
    }
}

private struct PopRocketAccessoryWidget: Widget {
    let kind = "PopRocketAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardWidgetProvider()) { entry in
            AccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("PopRocket Quick Status")
        .description("Shows cached compact homelab health on the Lock Screen.")
        .supportedFamilies(Self.supportedFamilies)
    }

    private static var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.accessoryInline, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }
}

private struct DashboardWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardWidgetEntry {
        DashboardWidgetEntry(
            date: Date(),
            cards: [],
            cardsStale: true,
            dashboardState: nil,
            commandShortcuts: [],
            actionSelections: [],
            actionRunRecords: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardWidgetEntry>) -> Void) {
        let entry = loadEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func loadEntry() -> DashboardWidgetEntry {
        let cache = AppGroupCache()
        let cachedCards = try? cache.loadCards()
        let dashboardState = try? cache.loadActiveDashboardState()
        let commandShortcuts = (try? cache.loadCommandShortcuts()?.shortcuts) ?? []
        let actionSelections = (try? cache.loadWidgetActionSelections()?.selections) ?? []
        let actionRunRecords = (try? cache.loadWidgetActionRunRecords()?.records) ?? []
        return DashboardWidgetEntry(
            date: Date(),
            cards: cachedCards?.cards ?? [],
            cardsStale: cachedCards?.isStale ?? true,
            dashboardState: dashboardState,
            commandShortcuts: commandShortcuts,
            actionSelections: actionSelections,
            actionRunRecords: actionRunRecords
        )
    }
}

private struct DashboardWidgetEntry: TimelineEntry {
    let date: Date
    let cards: [CardSnapshot]
    let cardsStale: Bool
    let dashboardState: CachedDashboardState?
    let commandShortcuts: [CommandShortcut]
    let actionSelections: [WidgetActionSelection]
    let actionRunRecords: [WidgetActionRunRecord]

    var monitors: [HealthMonitor] {
        dashboardState?.healthMonitors ?? []
    }

    var wolTargets: [WOLTarget] {
        dashboardState?.wolTargets ?? []
    }

    var sortedMonitors: [HealthMonitor] {
        monitors.sorted { lhs, rhs in
            let lhsStatus = MonitorStatusKind.status(for: lhs)
            let rhsStatus = MonitorStatusKind.status(for: rhs)
            if lhsStatus.rank != rhsStatus.rank {
                return lhsStatus.rank < rhsStatus.rank
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var activeCommandShortcuts: [CommandShortcut] {
        guard let bridgeID = dashboardState?.bridgeID else {
            return []
        }
        return commandShortcuts
            .filter { $0.bridgeID == bridgeID }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastRunAt ?? .distantPast
                let rhsDate = rhs.lastRunAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var activeWOLTargets: [WOLTarget] {
        wolTargets.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var selectedActions: [ResolvedWidgetAction] {
        guard let bridgeID = dashboardState?.bridgeID else {
            return []
        }
        return actionSelections
            .filter { $0.bridgeID == bridgeID }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.addedAt < rhs.addedAt
            }
            .compactMap(resolveAction)
    }

    var totalActionCount: Int {
        selectedActions.count
    }

    var visibleActions: [ResolvedWidgetAction] {
        Array(selectedActions.prefix(3))
    }

    var hiddenActionCount: Int {
        max(0, totalActionCount - visibleActions.count)
    }

    var hasDashboardCache: Bool {
        dashboardState != nil
    }

    var bridgeIsOffline: Bool {
        dashboardState?.bridgeReachable == false
    }

    var bridgeEvidenceText: String {
        guard let dashboardState else {
            return "No cache yet"
        }
        return "\(bridgeStatusSummary) · checked \(Self.relativeAge(since: dashboardState.writtenAt, now: date))"
    }

    var bridgeStatusSummary: String {
        guard
            let rawStatus = dashboardState?.bridgeStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawStatus.isEmpty
        else {
            return bridgeIsOffline ? "Offline" : "Cached"
        }
        switch rawStatus.lowercased() {
        case "connection failed", "cannot connect", "unreachable", "offline":
            return "Offline"
        case "checking connection":
            return "Pending"
        case "online", "ok", "connected", "healthy":
            return "Confirmed"
        default:
            return rawStatus
        }
    }

    private var latestActionRunBySelectionID: [String: WidgetActionRunRecord] {
        Dictionary(grouping: actionRunRecords, by: \.id).compactMapValues { records in
            records.max { lhs, rhs in
                lhs.ranAt < rhs.ranAt
            }
        }
    }

    var totalMonitorCount: Int {
        monitors.count
    }

    var upCount: Int {
        monitors.filter { MonitorStatusKind.status(for: $0) == .up }.count
    }

    var downCount: Int {
        monitors.filter { MonitorStatusKind.status(for: $0) == .down }.count
    }

    var unknownCount: Int {
        monitors.filter { MonitorStatusKind.status(for: $0) == .unknown }.count
    }

    var overallStatus: MonitorStatusKind {
        if bridgeIsOffline {
            return .down
        }
        if totalMonitorCount == 0 {
            return .unknown
        }
        if healthIsStale {
            return .unknown
        }
        if downCount > 0 {
            return .down
        }
        if unknownCount > 0 {
            return .unknown
        }
        return .up
    }

    var headline: String {
        guard dashboardState != nil else {
            return "No Cache"
        }
        if bridgeIsOffline {
            return "Bridge Offline"
        }
        if totalMonitorCount == 0 {
            return "No Checks"
        }
        if healthIsStale {
            if downCount > 0 {
                return downCount == 1 ? "Cached Down" : "\(downCount) Cached Down"
            }
            if unknownCount > 0 {
                return unknownCount == 1 ? "Cached Check" : "\(unknownCount) Cached Check"
            }
            return "Cached Up"
        }
        if downCount > 0 {
            return downCount == 1 ? "1 Confirmed Down" : "\(downCount) Confirmed Down"
        }
        if unknownCount > 0 {
            return unknownCount == 1 ? "1 Check Unknown" : "\(unknownCount) Checks Unknown"
        }
        return "Confirmed Up"
    }

    var bridgeLabel: String {
        if let name = dashboardState?.bridgeName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let bridgeID = dashboardState?.bridgeID.trimmingCharacters(in: .whitespacesAndNewlines), !bridgeID.isEmpty {
            return Self.shortBridgeID(bridgeID)
        }
        return "No bridge"
    }

    var statusSubtitle: String {
        if bridgeIsOffline {
            return "\(bridgeLabel) · \(bridgeEvidenceText)"
        }
        return "\(bridgeLabel) · \(freshnessText)"
    }

    var healthSubtitle: String {
        if bridgeIsOffline {
            return "\(bridgeLabel) · \(bridgeEvidenceText)"
        }
        return "\(bridgeLabel) · \(healthFreshnessText)"
    }

    var actionsSubtitle: String {
        guard dashboardState != nil else {
            return "No bridge cache · Open app"
        }
        if bridgeIsOffline {
            return "\(bridgeLabel) · Offline · open app"
        }
        if totalActionCount == 0 {
            return "\(bridgeLabel) · No trusted actions"
        }
        if selectedActions.contains(where: { !$0.isRunnable }) {
            return "\(bridgeLabel) · Open app to refresh actions"
        }
        return "\(bridgeLabel) · Trusted only · \(actionFreshnessText)"
    }

    var actionWidgetStatus: MonitorStatusKind {
        guard dashboardState != nil, totalActionCount > 0 else {
            return .unknown
        }
        if bridgeIsOffline {
            return .down
        }
        if selectedActions.contains(where: { !$0.isRunnable }) {
            return .unknown
        }
        if selectedActions.contains(where: { $0.lastRun?.succeeded == false }) {
            return .down
        }
        if !actionCacheIsStale, selectedActions.contains(where: { $0.lastRun?.succeeded == true }) {
            return .up
        }
        return .unknown
    }

    var actionWidgetBadgeText: String {
        guard dashboardState != nil else {
            return "No Cache"
        }
        if bridgeIsOffline {
            return "Offline"
        }
        guard totalActionCount > 0 else {
            return "None"
        }
        if selectedActions.contains(where: { !$0.isRunnable }) {
            return "Open App"
        }
        return actionCacheIsStale ? "Cached" : "Trusted"
    }

    var statusFreshnessBadgeText: String {
        if bridgeIsOffline {
            return "Offline"
        }
        return dashboardState == nil ? "No Cache" : (healthIsStale ? "Stale" : "Cached")
    }

    var healthFreshnessBadgeText: String {
        guard dashboardState != nil else {
            return "No Cache"
        }
        if bridgeIsOffline {
            return "Offline"
        }
        return monitors.isEmpty ? "None" : (healthIsStale ? "Stale" : "Cached")
    }

    var freshnessText: String {
        if bridgeIsOffline {
            return bridgeEvidenceText
        }
        guard let lastUpdated else {
            return "No cache yet"
        }
        let relative = Self.relativeAge(since: lastUpdated, now: date)
        if healthIsStale || (!cards.isEmpty && cardsStale) {
            return "Stale · checked \(relative)"
        }
        return "Cached · checked \(relative)"
    }

    var lastUpdated: Date? {
        healthLastUpdated
            ?? dashboardState?.wolTargetsUpdatedAt
            ?? dashboardState?.writtenAt
            ?? cards.map(\.updatedAt).max()
    }

    var healthFreshnessText: String {
        if bridgeIsOffline {
            return bridgeEvidenceText
        }
        guard let timestamp = healthLastUpdated else {
            return dashboardState == nil ? "No health cache" : "No checks"
        }
        let relative = Self.relativeAge(since: timestamp, now: date)
        return healthIsStale ? "Stale · checked \(relative)" : "Cached · checked \(relative)"
    }

    var healthIsStale: Bool {
        if bridgeIsOffline {
            return true
        }
        guard let healthLastUpdated else {
            return true
        }
        return date.timeIntervalSince(healthLastUpdated) > 15 * 60
    }

    var actionFreshnessText: String {
        if bridgeIsOffline {
            return bridgeEvidenceText
        }
        guard let timestamp = actionLastUpdated else {
            return dashboardState == nil ? "No bridge cache" : "No action cache"
        }
        let relative = Self.relativeAge(since: timestamp, now: date)
        return actionCacheIsStale ? "Stale · updated \(relative)" : "Cached · updated \(relative)"
    }

    var actionCacheIsStale: Bool {
        if bridgeIsOffline {
            return true
        }
        guard let timestamp = actionLastUpdated else {
            return true
        }
        return date.timeIntervalSince(timestamp) > 15 * 60
    }

    private var actionDisabledReason: String? {
        if bridgeIsOffline {
            return "Offline"
        }
        if actionCacheIsStale {
            return "Open App"
        }
        return nil
    }

    private var bridgeOfflineActionSubtitle: String? {
        bridgeIsOffline ? "Bridge offline · open app" : nil
    }

    private var healthLastUpdated: Date? {
        dashboardState?.healthMonitorsUpdatedAt
            ?? monitors.compactMap(\.checkedAt).max()
    }

    private var actionLastUpdated: Date? {
        let activeBridgeID = dashboardState?.bridgeID
        return [
            dashboardState?.wolTargetsUpdatedAt,
            dashboardState?.writtenAt,
            actionSelections
                .filter { selection in
                    guard let activeBridgeID else { return false }
                    return selection.bridgeID == activeBridgeID
                }
                .map(\.addedAt)
                .max(),
            actionRunRecords
                .filter { record in
                    guard let activeBridgeID else { return false }
                    return record.bridgeID == activeBridgeID
                }
                .map(\.ranAt)
                .max(),
            activeCommandShortcuts.compactMap(\.lastRunAt).max(),
        ]
        .compactMap { $0 }
        .max()
    }

    private static func relativeAge(since timestamp: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(timestamp)))
        if seconds < 60 {
            return "now"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        return "\(hours / 24)d ago"
    }

    private static func shortBridgeID(_ value: String) -> String {
        if value.count <= 16 {
            return value
        }
        return String(value.prefix(16))
    }

    private static func nonBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveAction(_ selection: WidgetActionSelection) -> ResolvedWidgetAction? {
        let lastRun = latestActionRunBySelectionID[selection.id]
        let disabledReason = actionDisabledReason
        let actionIsStale = disabledReason != nil || actionCacheIsStale
        switch selection.kind {
        case .wol:
            guard let target = activeWOLTargets.first(where: { $0.id == selection.actionID }) else {
                return ResolvedWidgetAction(
                    id: selection.id,
                    bridgeID: selection.bridgeID,
                    bridgeName: bridgeLabel,
                    kind: .wol,
                    actionID: selection.actionID,
                    title: Self.nonBlank(selection.title) ?? "Wake Target",
                    subtitle: "Device cache missing · open app",
                    systemImage: "power",
                    tint: WidgetDesign.Palette.stale,
                    isStale: true,
                    lastRun: lastRun,
                    isRunnable: false,
                    disabledReason: "Open App"
                )
            }
            return ResolvedWidgetAction(
                id: selection.id,
                bridgeID: selection.bridgeID,
                bridgeName: bridgeLabel,
                kind: .wol,
                    actionID: selection.actionID,
                    title: "Wake \(target.name)",
                    subtitle: bridgeOfflineActionSubtitle ?? Self.actionSubtitle(
                        kind: .wol,
                        lastRun: lastRun,
                        now: date,
                        isStale: actionIsStale,
                        lastConfirmedAt: actionLastUpdated
                    ),
                    systemImage: "power",
                    tint: Self.actionTint(kind: .wol, lastRun: lastRun, isStale: actionIsStale),
                    isStale: actionIsStale,
                    lastRun: lastRun,
                    isRunnable: disabledReason == nil,
                    disabledReason: disabledReason
                )
        case .command:
            guard
                let uuid = UUID(uuidString: selection.actionID),
                let shortcut = activeCommandShortcuts.first(where: { $0.id == uuid })
            else {
                return ResolvedWidgetAction(
                    id: selection.id,
                    bridgeID: selection.bridgeID,
                    bridgeName: bridgeLabel,
                    kind: .command,
                    actionID: selection.actionID,
                    title: Self.nonBlank(selection.title) ?? "Command Tile",
                    subtitle: "Command cache missing · open app",
                    systemImage: "terminal.fill",
                    tint: WidgetDesign.Palette.stale,
                    isStale: true,
                    lastRun: lastRun,
                    isRunnable: false,
                    disabledReason: "Open App"
                )
            }
            return ResolvedWidgetAction(
                id: selection.id,
                bridgeID: selection.bridgeID,
                bridgeName: bridgeLabel,
                kind: .command,
                    actionID: selection.actionID,
                    title: shortcut.name,
                    subtitle: bridgeOfflineActionSubtitle ?? Self.actionSubtitle(
                        kind: .command,
                        lastRun: lastRun,
                        now: date,
                        isStale: actionIsStale,
                        lastConfirmedAt: actionLastUpdated
                    ),
                    systemImage: "terminal.fill",
                    tint: Self.actionTint(kind: .command, lastRun: lastRun, isStale: actionIsStale),
                    isStale: actionIsStale,
                    lastRun: lastRun,
                    isRunnable: disabledReason == nil,
                    disabledReason: disabledReason
                )
        }
    }

    private static func actionSubtitle(
        kind: WidgetActionKind,
        lastRun: WidgetActionRunRecord?,
        now: Date,
        isStale: Bool,
        lastConfirmedAt: Date?
    ) -> String? {
        let noun: String
        switch kind {
        case .wol:
            noun = "wake action"
        case .command:
            noun = "command tile"
        }
        if isStale {
            let confirmation = lastConfirmedAt.map { "updated \(relativeAge(since: $0, now: now))" } ?? "cached"
            guard let lastRun else {
                return "\(confirmation) · \(noun)"
            }
            let label = lastRun.succeeded ? "Sent" : "Failed"
            return "\(label) \(relativeAge(since: lastRun.ranAt, now: now)) · \(confirmation)"
        }
        guard let lastRun else {
            return "Trusted \(noun)"
        }
        let label = lastRun.succeeded ? "Sent" : "Failed"
        let runText = "\(label) \(relativeAge(since: lastRun.ranAt, now: now))"
        return "\(runText) · \(noun)"
    }

    var statusEmptyText: String {
        if dashboardState == nil {
            return "Open app once"
        }
        return "Add health checks"
    }

    var healthEmptyTitle: String {
        dashboardState == nil ? "No cached health" : "No checks yet"
    }

    var healthEmptyDetail: String {
        dashboardState == nil ? "Open the app once." : "Add TCP or HTTP checks."
    }

    var actionsEmptyTitle: String {
        dashboardState == nil ? "No bridge cache" : "No trusted actions"
    }

    var actionsEmptyDetail: String {
        dashboardState == nil ? "Open the app once." : "Trust action tiles."
    }

    var wakeTargetSummary: String {
        guard dashboardState != nil else {
            return "No bridge cache"
        }
        if totalActionCount > 0 {
            return totalActionCount == 1 ? "1 trusted action" : "\(totalActionCount) trusted actions"
        }
        let count = wolTargets.count
        if count == 0 {
            return "No wake targets"
        }
        return count == 1 ? "1 wake target" : "\(count) wake targets"
    }

    private static func actionTint(kind: WidgetActionKind, lastRun: WidgetActionRunRecord?, isStale: Bool) -> Color {
        if lastRun?.succeeded == false {
            return WidgetDesign.Palette.warning
        }
        if lastRun?.succeeded == true {
            return WidgetDesign.Palette.success
        }
        if isStale {
            return WidgetDesign.Palette.stale
        }
        switch kind {
        case .wol:
            return WidgetDesign.Palette.wake
        case .command:
            return WidgetDesign.Palette.command
        }
    }
}

private struct ResolvedWidgetAction: Identifiable {
    let id: String
    let bridgeID: String
    let bridgeName: String
    let kind: WidgetActionKind
    let actionID: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let isStale: Bool
    let lastRun: WidgetActionRunRecord?
    let isRunnable: Bool
    let disabledReason: String?
}

private enum PopRocketWidgetDeepLink {
    static let home = URL(string: "poprocket://home")
    static let monitors = URL(string: "poprocket://monitors")
    static let actions = URL(string: "poprocket://actions")
}

private enum MonitorStatusKind: Equatable {
    case up
    case down
    case unknown

    static func status(for monitor: HealthMonitor) -> MonitorStatusKind {
        switch monitor.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "up", "ok", "online", "healthy", "ready":
            return .up
        case "down", "failed", "failure", "offline", "error", "unhealthy":
            return .down
        default:
            return .unknown
        }
    }

    var label: String {
        switch self {
        case .up:
            return "Up"
        case .down:
            return "Down"
        case .unknown:
            return "Unknown"
        }
    }

    var rank: Int {
        switch self {
        case .down:
            return 0
        case .unknown:
            return 1
        case .up:
            return 2
        }
    }

    var color: Color {
        switch self {
        case .up:
            return WidgetDesign.Palette.success
        case .down:
            return WidgetDesign.Palette.warning
        case .unknown:
            return WidgetDesign.Palette.stale
        }
    }

    var symbolName: String {
        switch self {
        case .up:
            return "checkmark.circle.fill"
        case .down:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

private enum WidgetDesign {
    enum Palette {
        // Keep widget status color meanings aligned with the app.
        static let action = Color(lightHex: 0x2563EB, darkHex: 0x60A5FA)
        static let bridge = Color(lightHex: 0x0891B2, darkHex: 0x22D3EE)
        static let wake = Color(lightHex: 0x7C3AED, darkHex: 0xA78BFA)
        static let command = Color(lightHex: 0x4F46E5, darkHex: 0x818CF8)
        static let success = Color(lightHex: 0x16A34A, darkHex: 0x4ADE80)
        static let warning = Color(lightHex: 0xD97706, darkHex: 0xFBBF24)
        static let stale = Color(lightHex: 0x64748B, darkHex: 0x94A3B8)
    }

    static let panelFill = Color.primary.opacity(0.07)
    static let panelStroke = Color.primary.opacity(0.09)
    static let mutedFill = Palette.stale.opacity(0.14)
    static let cornerRadius: CGFloat = 10
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    init(lightHex: UInt32, darkHex: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
        #else
        self.init(hex: lightHex)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(hex & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
#endif

private struct WidgetSemanticPanelModifier: ViewModifier {
    let tint: Color
    var isActive = true
    var showsRail = true

    func body(content: Content) -> some View {
        let resolvedTint = isActive ? tint : WidgetDesign.Palette.stale
        content
            .background {
                RoundedRectangle(cornerRadius: WidgetDesign.cornerRadius, style: .continuous)
                    .fill(WidgetDesign.panelFill)
                RoundedRectangle(cornerRadius: WidgetDesign.cornerRadius, style: .continuous)
                    .fill(resolvedTint.opacity(isActive ? 0.07 : 0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: WidgetDesign.cornerRadius, style: .continuous)
                    .stroke(resolvedTint.opacity(isActive ? 0.24 : 0.16), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if showsRail {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(resolvedTint.opacity(isActive ? 0.78 : 0.30))
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: WidgetDesign.cornerRadius, style: .continuous))
    }
}

private extension View {
    func widgetSemanticPanel(tint: Color, isActive: Bool = true, showsRail: Bool = true) -> some View {
        modifier(WidgetSemanticPanelModifier(tint: tint, isActive: isActive, showsRail: showsRail))
    }
}

private struct StatusWidgetView: View {
    let entry: DashboardWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(
                title: "Homelab",
                subtitle: entry.statusSubtitle,
                status: entry.overallStatus,
                badgeText: entry.statusFreshnessBadgeText,
                systemImage: "gauge.with.dots.needle.33percent"
            )
            Spacer(minLength: 0)
            Text(entry.headline)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            if entry.totalMonitorCount > 0 {
                HStack(spacing: 6) {
                    MetricPill(
                        value: "\(entry.upCount)",
                        label: "Up",
                        color: entry.healthIsStale ? WidgetDesign.Palette.stale : WidgetDesign.Palette.success
                    )
                    if entry.downCount > 0 {
                        MetricPill(
                            value: "\(entry.downCount)",
                            label: "Down",
                            color: entry.healthIsStale ? WidgetDesign.Palette.stale : WidgetDesign.Palette.warning
                        )
                    } else if entry.unknownCount > 0 {
                        MetricPill(value: "\(entry.unknownCount)", label: "Check", color: WidgetDesign.Palette.stale)
                    }
                }
            } else {
                Text(entry.statusEmptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: entry.totalActionCount > 0 ? "checkmark.seal.fill" : "power")
                Text(entry.wakeTargetSummary)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .containerBackground(.background, for: .widget)
        .widgetURL(PopRocketWidgetDeepLink.home)
    }
}

private struct HealthWidgetView: View {
    let entry: DashboardWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(
                title: "Health",
                subtitle: entry.healthSubtitle,
                status: entry.overallStatus,
                badgeText: entry.healthFreshnessBadgeText,
                systemImage: "waveform.path.ecg"
            )

            if entry.sortedMonitors.isEmpty {
                Spacer(minLength: 0)
                EmptyWidgetState(
                    systemImage: "waveform.path.ecg",
                    title: entry.healthEmptyTitle,
                    detail: entry.healthEmptyDetail
                )
                Spacer(minLength: 0)
            } else {
                WidgetHealthSummaryStrip(
                    upCount: entry.upCount,
                    downCount: entry.downCount,
                    unknownCount: entry.unknownCount,
                    stale: entry.healthIsStale
                )

                VStack(spacing: 7) {
                    ForEach(Array(entry.sortedMonitors.prefix(3))) { monitor in
                        MonitorRow(monitor: monitor, stale: entry.healthIsStale)
                    }
                }
                if entry.sortedMonitors.count > 3 {
                    Text("+\(entry.sortedMonitors.count - 3) more monitors")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .containerBackground(.background, for: .widget)
        .widgetURL(PopRocketWidgetDeepLink.monitors)
    }
}

private struct ActionsWidgetView: View {
    let entry: DashboardWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(
                title: "Actions",
                subtitle: entry.actionsSubtitle,
                status: entry.actionWidgetStatus,
                badgeText: entry.actionWidgetBadgeText,
                systemImage: "bolt.circle"
            )

            if entry.totalActionCount == 0 {
                Spacer(minLength: 0)
                EmptyWidgetState(
                    systemImage: "bolt.badge.clock",
                    title: entry.actionsEmptyTitle,
                    detail: entry.actionsEmptyDetail
                )
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.visibleActions) { action in
                        actionRow(for: action)
                    }
                }
                if entry.hiddenActionCount > 0 {
                    Text("+\(entry.hiddenActionCount) more trusted")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .containerBackground(.background, for: .widget)
        .widgetURL(PopRocketWidgetDeepLink.actions)
    }

    @ViewBuilder
    private func actionRow(for action: ResolvedWidgetAction) -> some View {
        if action.isRunnable {
            switch action.kind {
            case .wol:
                Button(intent: RunActionIntent(
                    actionID: "wol:\(action.actionID)",
                    eventID: nil,
                    bridgeID: action.bridgeID
                )) {
                    widgetActionRow(for: action)
                }
                .buttonStyle(.plain)
            case .command:
                Button(intent: RunCommandShortcutIntent(shortcutID: action.actionID)) {
                    widgetActionRow(for: action)
                }
                .buttonStyle(.plain)
            }
        } else {
            widgetActionRow(for: action)
        }
    }

    private func widgetActionRow(for action: ResolvedWidgetAction) -> WidgetActionRow {
        WidgetActionRow(
            title: action.title,
            subtitle: action.subtitle ?? fallbackSubtitle(for: action.kind),
            bridgeName: action.bridgeName,
            systemImage: action.systemImage,
            tint: action.tint,
            stale: action.isStale,
            lastRun: action.lastRun,
            disabledReason: action.disabledReason
        )
    }

    private func fallbackSubtitle(for kind: WidgetActionKind) -> String {
        switch kind {
        case .wol:
            return "Wake-on-LAN"
        case .command:
            return "Command tile"
        }
    }
}

private struct WidgetActionRow: View {
    let title: String
    let subtitle: String
    let bridgeName: String
    let systemImage: String
    let tint: Color
    let stale: Bool
    let lastRun: WidgetActionRunRecord?
    let disabledReason: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(displayTint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Label(bridgeName, systemImage: "antenna.radiowaves.left.and.right")
                        Text("·")
                        Text(subtitle)
                    }
                    Text("\(bridgeName) · \(subtitle)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            WidgetActionStatusChip(stale: stale, lastRun: lastRun, disabledReason: disabledReason)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .widgetSemanticPanel(tint: displayTint, isActive: rowIsActive)
        .opacity(stale && lastRun?.succeeded != false ? 0.82 : 1)
    }

    private var displayTint: Color {
        if disabledReason == "Offline" {
            return WidgetDesign.Palette.warning
        }
        if lastRun?.succeeded == false {
            return WidgetDesign.Palette.warning
        }
        return stale ? WidgetDesign.Palette.stale : tint
    }

    private var rowIsActive: Bool {
        if disabledReason == "Offline" {
            return true
        }
        return !stale || lastRun?.succeeded == false
    }
}

private struct WidgetActionStatusChip: View {
    let stale: Bool
    let lastRun: WidgetActionRunRecord?
    let disabledReason: String?

    var body: some View {
        Label(visibleTitle, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(title)
    }

    private var visibleTitle: String {
        if let disabledReason {
            return disabledReason
        }
        if let lastRun {
            if stale, lastRun.succeeded {
                return "Cached"
            }
            return lastRun.succeeded ? "Sent" : "Failed"
        }
        if stale {
            return "Cached"
        }
        return "Trusted"
    }

    private var title: String {
        if let disabledReason {
            return "Trusted action unavailable. \(disabledReason)"
        }
        if let lastRun {
            let stalePrefix = stale ? "Cached trusted action. " : ""
            if stale, lastRun.succeeded {
                return stalePrefix + "Last successful run is cached"
            }
            return stalePrefix + (lastRun.succeeded ? "Last run succeeded" : "Last run failed")
        }
        if stale {
            return "Cached trusted action"
        }
        return "Trusted action"
    }

    private var systemImage: String {
        if disabledReason == "Offline" {
            return "wifi.slash"
        }
        if disabledReason != nil {
            return "lock.fill"
        }
        if let lastRun {
            if stale, lastRun.succeeded {
                return "clock.badge.exclamationmark"
            }
            return lastRun.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        }
        if stale {
            return "clock.badge.exclamationmark"
        }
        return "checkmark.seal.fill"
    }

    private var tint: Color {
        if disabledReason == "Offline" {
            return WidgetDesign.Palette.warning
        }
        if disabledReason != nil {
            return WidgetDesign.Palette.stale
        }
        if let lastRun {
            if stale, lastRun.succeeded {
                return WidgetDesign.Palette.stale
            }
            return lastRun.succeeded ? WidgetDesign.Palette.success : WidgetDesign.Palette.warning
        }
        if stale {
            return WidgetDesign.Palette.stale
        }
        return WidgetDesign.Palette.bridge
    }
}

private struct AccessoryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: DashboardWidgetEntry

    var body: some View {
        Group {
        #if os(iOS)
            switch family {
            case .accessoryInline:
                Text("Homelab \(entry.headline) · \(entry.freshnessText)")
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: entry.overallStatus.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .widgetAccentable()
                    Text(circularLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Homelab", systemImage: entry.overallStatus.symbolName)
                        .font(.caption.weight(.semibold))
                    Text(entry.headline)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.statusSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            default:
                StatusWidgetView(entry: entry)
            }
        #else
            StatusWidgetView(entry: entry)
        #endif
        }
        .widgetURL(PopRocketWidgetDeepLink.home)
    }

    private var circularLabel: String {
        if entry.totalMonitorCount == 0 {
            return "None"
        }
        if entry.healthIsStale {
            return "Stale"
        }
        if entry.downCount > 0 {
            return "\(entry.downCount)"
        }
        return "Up"
    }
}

private struct WidgetHeader: View {
    let title: String
    let subtitle: String
    let status: MonitorStatusKind
    let badgeText: String?
    let systemImage: String

    init(
        title: String,
        subtitle: String,
        status: MonitorStatusKind,
        badgeText: String? = nil,
        systemImage: String = "dot.radiowaves.left.and.right"
    ) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.badgeText = badgeText
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(status.color)
                .frame(width: 24, height: 24)
                .background(status.color.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            StatusBadge(status: status, label: badgeText)
        }
    }
}

private struct StatusBadge: View {
    let status: MonitorStatusKind
    let label: String?

    init(status: MonitorStatusKind, label: String? = nil) {
        self.status = status
        self.label = label
    }

    var body: some View {
        Text(label ?? status.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        guard let label else {
            return status.color
        }
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cached", "stale", "none", "no cache":
            return WidgetDesign.Palette.stale
        case "trusted":
            return WidgetDesign.Palette.bridge
        default:
            return status.color
        }
    }
}

private struct MetricPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(color.opacity(0.13), in: Capsule())
    }
}

private struct WidgetHealthSummaryStrip: View {
    let upCount: Int
    let downCount: Int
    let unknownCount: Int
    let stale: Bool

    var body: some View {
        HStack(spacing: 6) {
            WidgetHealthSummaryCell(
                value: "\(upCount)",
                label: "Up",
                systemImage: "checkmark.circle.fill",
                color: upCount > 0 && !stale ? WidgetDesign.Palette.success : WidgetDesign.Palette.stale
            )
            WidgetHealthSummaryCell(
                value: "\(downCount)",
                label: "Down",
                systemImage: "exclamationmark.triangle.fill",
                color: downCount > 0 && !stale ? WidgetDesign.Palette.warning : WidgetDesign.Palette.stale
            )
            WidgetHealthSummaryCell(
                value: "\(unknownCount)",
                label: "Check",
                systemImage: "questionmark.circle.fill",
                color: WidgetDesign.Palette.stale
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(upCount) up, \(downCount) down, \(unknownCount) unknown\(stale ? ", cached" : "")")
    }
}

private struct WidgetHealthSummaryCell: View {
    let value: String
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(value)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct MonitorRow: View {
    let monitor: HealthMonitor
    let stale: Bool

    private var status: MonitorStatusKind {
        MonitorStatusKind.status(for: monitor)
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: status.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(stale ? WidgetDesign.Palette.stale : status.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if stale {
                if let checkedAt = monitor.checkedAt {
                    Text("Cached · checked \(checkedAt, style: .relative)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    Text("Cached")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let checkedAt = monitor.checkedAt {
                Text("Cached · checked \(checkedAt, style: .relative)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else if status != .up {
                Text(status.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.color)
                    .lineLimit(1)
            } else if let responseTime = monitor.responseTimeMS {
                Text("\(responseTime) ms")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .widgetSemanticPanel(tint: rowTint, isActive: !stale)
        .opacity(stale ? 0.82 : 1)
    }

    private var rowTint: Color {
        stale ? WidgetDesign.Palette.stale : status.color
    }

    private var detailText: String {
        if let message = monitor.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty, status != .up {
            return message
        }
        if let url = monitor.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            return url
        }
        if let host = monitor.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            if let port = monitor.port {
                return "\(host):\(port)"
            }
            return host
        }
        return monitor.kind.uppercased()
    }
}

private struct EmptyWidgetState: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(WidgetDesign.mutedFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .widgetSemanticPanel(tint: WidgetDesign.Palette.stale, isActive: false)
    }
}
