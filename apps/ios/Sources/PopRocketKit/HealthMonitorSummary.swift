import Foundation

public enum HealthMonitorStatusCategory: Int, Comparable {
    case down = 0
    case unknown = 1
    case up = 2

    public static func < (lhs: HealthMonitorStatusCategory, rhs: HealthMonitorStatusCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func status(for monitor: HealthMonitor) -> HealthMonitorStatusCategory {
        status(for: monitor.status)
    }

    public static func status(for value: String) -> HealthMonitorStatusCategory {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "down": return .down
        case "up": return .up
        default: return .unknown
        }
    }

    public var normalizedValue: String {
        switch self {
        case .down: return "down"
        case .unknown: return "unknown"
        case .up: return "up"
        }
    }

    public var label: String {
        switch self {
        case .down: return "Down"
        case .unknown: return "Unknown"
        case .up: return "Up"
        }
    }
}

public struct HealthMonitorSummary {
    public let sortedMonitors: [HealthMonitor]
    public let downMonitors: [HealthMonitor]
    public let unknownMonitors: [HealthMonitor]
    public let upMonitors: [HealthMonitor]

    public init(monitors: [HealthMonitor]) {
        let sorted = monitors.sorted { lhs, rhs in
            let lhsStatus = HealthMonitorStatusCategory.status(for: lhs)
            let rhsStatus = HealthMonitorStatusCategory.status(for: rhs)
            if lhsStatus == rhsStatus {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhsStatus < rhsStatus
        }
        sortedMonitors = sorted
        downMonitors = sorted.filter { HealthMonitorStatusCategory.status(for: $0) == .down }
        unknownMonitors = sorted.filter { HealthMonitorStatusCategory.status(for: $0) == .unknown }
        upMonitors = sorted.filter { HealthMonitorStatusCategory.status(for: $0) == .up }
    }

    public var alertMonitors: [HealthMonitor] { downMonitors + unknownMonitors }
    public var upCount: Int { upMonitors.count }
    public var downCount: Int { downMonitors.count }
    public var unknownCount: Int { unknownMonitors.count }
}
